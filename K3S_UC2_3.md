# ACRAM deployment on the uc2-3 k3s cluster

The Minikube profile named `acram` is a separate Kubernetes cluster. Workloads
running there do not appear in the host k3s API or in Rafa's k3s console. This
runbook performs a controlled cutover to the system k3s cluster while keeping
the Minikube deployment available for rollback.

The k3s overlay:

- runs one ACRAM replica in namespace `acram`;
- pins it to the node whose `kubernetes.io/hostname` is `uc2-3`;
- uses the locally built image `docker.io/library/acram:r2025b-wsfix1` with
  `imagePullPolicy: Never`;
- keeps the Nokia configuration, credentials Secret, PVC, security context,
  probes, and resource limits from the base manifests;
- allows up to 75 minutes for the startup probe; and
- exports risk graphs through the native SVG backend.

Do not run the Minikube and k3s replicas together. Both would consume the same
ADI input and could publish duplicate transactions.

## 1. Confirm cluster access and capacity

Run on `uc2-3`:

```bash
source "$HOME/acram-local/env.sh"

sudo systemctl is-active k3s-agent
sudo systemctl is-enabled k3s-agent
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get node uc2-3 \
  -o jsonpath='{.metadata.labels.kubernetes\.io/hostname}{"\n"}'
sudo k3s kubectl describe node uc2-3 |
  sed -n '/Taints:/p;/Allocatable:/,+7p'
sudo k3s kubectl get storageclass
df -h /var/lib/rancher/k3s
```

The hostname command must print `uc2-3`. Change the node selector in
`k3s/deployment-patch.yaml` if the cluster uses another node name.
The node must be Ready, `amd64`, schedulable, free of untolerated taints, and
have enough allocatable CPU and memory. At least one StorageClass must be marked
`(default)`; otherwise stop and ask Rafa which class to add to the PVC.
Keep at least 40 GiB free for the 11 GiB image, its unpacked snapshot, runtime
cache, and cluster headroom. Confirm the namespace and local-image policy with
Rafa before the production cutover. Ask Rafa for namespace-scoped access rather
than sharing the administrator kubeconfig. Also confirm that namespace egress
can reach DNS, SmartQC at `192.168.1.238:8080`, and HTTPS if NVD access is
enabled.

## 2. Build the fixed image in the node runtime

The `uc2-3` k3s agent uses the root Docker daemon at
`unix:///var/run/docker.sock`. Images imported into a standalone containerd
socket are invisible to this kubelet and cause `ErrImageNeverPull`.

Copy the small compiled overlay bundle from the Windows project directory:

```powershell
scp .\dist\acram-r2025b-wsfix1-build.tar.gz `
  dmytro@192.168.1.237:~/acram-local/
```

Then run on `uc2-3`:

```bash
BASE_IMAGE='docker.io/library/acram:r2025b-pyfix1'
TARGET_IMAGE='docker.io/library/acram:r2025b-wsfix1'
BUNDLE="$HOME/acram-local/acram-r2025b-wsfix1-build.tar.gz"
BUILD_DIR="$HOME/acram-local/wsfix1-build"

test -s "$BUNDLE"
mkdir -p "$BUILD_DIR"
tar -xzf "$BUNDLE" -C "$BUILD_DIR"

sudo /usr/bin/docker --host unix:///var/run/docker.sock \
  image inspect "$BASE_IMAGE" >/dev/null

sudo /usr/bin/docker --host unix:///var/run/docker.sock build \
  --pull=false \
  --file "$BUILD_DIR/docker/Dockerfile.app-overlay" \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --tag "$TARGET_IMAGE" \
  "$BUILD_DIR"

sudo /usr/bin/docker --host unix:///var/run/docker.sock \
  image inspect "$TARGET_IMAGE" \
  --format 'image={{.RepoTags}} id={{.Id}} size={{.Size}}'
```

Do not apply the Deployment until the final `image inspect` succeeds. Keep the
`r2025b-pyfix1` image until `wsfix1` is Ready and its reset test passes; it is
the rollback base. If the cluster provides an approved private registry,
pushing the final image there and changing the overlay to
`imagePullPolicy: IfNotPresent` is preferable to a node-local image.

## 3. Copy the ADI Secret without displaying it

Rotate the ADI key in SmartQC before this production cutover. Its previous
value appeared in terminal output, so the old credential should not be reused
in the shared cluster. Update the Minikube Secret with the rotated credential,
then use the commands below.

Create protected temporary files, copy the Secret data from Minikube, and
recreate the Secret in k3s. Do not enable shell tracing and do not print or
paste either file's contents.

```bash
cd "$HOME/acram-local/deploy"
umask 077

ACRAM_CREDENTIALS_TMP=$(mktemp "$HOME/.acram-credentials.XXXXXX.json")
ACRAM_NVD_TMP=$(mktemp "$HOME/.acram-nvd-key.XXXXXX")
trap 'rm -f "$ACRAM_CREDENTIALS_TMP" "$ACRAM_NVD_TMP"' EXIT

kubectl --context acram -n acram get secret acram-adi-credentials \
  -o jsonpath='{.data.credentials\.json}' |
  base64 --decode > "$ACRAM_CREDENTIALS_TMP"

kubectl --context acram -n acram get secret acram-adi-credentials \
  -o jsonpath='{.data.nvd-api-key}' |
  base64 --decode > "$ACRAM_NVD_TMP"

test -s "$ACRAM_CREDENTIALS_TMP"

sudo k3s kubectl apply -f k8s/namespace.yaml

sudo k3s kubectl -n acram create secret generic acram-adi-credentials \
  --from-file=credentials.json="$ACRAM_CREDENTIALS_TMP" \
  --from-file=nvd-api-key="$ACRAM_NVD_TMP" \
  --dry-run=client -o yaml |
  sudo k3s kubectl apply -f -

rm -f "$ACRAM_CREDENTIALS_TMP" "$ACRAM_NVD_TMP"
trap - EXIT
```

The NVD key is optional. When it was absent in Minikube, the recreated key is
empty and ACRAM continues without it.

## 4. Validate the rendered deployment

This is read-only and does not start ACRAM:

```bash
sudo k3s kubectl kustomize k3s |
  grep -E 'image:|imagePullPolicy:|kubernetes.io/hostname:|failureThreshold:|progressDeadlineSeconds:|terminationGracePeriodSeconds:'
```

Expected values include:

```text
image: docker.io/library/acram:r2025b-wsfix1
imagePullPolicy: Never
kubernetes.io/hostname: uc2-3
failureThreshold: 900
progressDeadlineSeconds: 5400
terminationGracePeriodSeconds: 180
```

## 5. Cut over without duplicate publishers

First stop the Minikube replica:

```bash
kubectl --context acram -n acram scale deployment/acram --replicas=0
kubectl --context acram -n acram wait --for=delete pod \
  -l app.kubernetes.io/name=acram --timeout=180s || true
kubectl --context acram -n acram get pods -o wide
```

Do not continue if an old ACRAM pod still exists. Then start ACRAM in the
shared k3s cluster:

```bash
sudo k3s kubectl apply -k k3s

sudo k3s kubectl -n acram rollout status deployment/acram \
  --timeout=95m
```

## 6. Verify that k3s and Jens's console can see ACRAM

```bash
sudo k3s kubectl get all -n acram -o wide
sudo k3s kubectl get pods -A -o wide | grep -w acram

sudo k3s kubectl -n acram logs -f deployment/acram \
  --since=10m --timestamps
```

The pod must be `Running`, become `1/1 Ready`, and show node `uc2-3`. The same
Deployment and Pod will then be returned by the shared k3s API used by the
console. ACRAM is outbound-only in ADI mode, so it does not require a Kubernetes
Service.

Verify the fixed WebSocket launcher and readiness probes:

```bash
sudo k3s kubectl -n acram exec deployment/acram -- \
  /opt/acram/healthcheck.sh startup
sudo k3s kubectl -n acram exec deployment/acram -- \
  /opt/acram/healthcheck.sh runtime
sudo k3s kubectl -n acram exec deployment/acram -- \
  sh -lc 'pid=$(cat /var/lib/acram/work/smartqc_pid.txt) && kill -0 "$pid" && echo "WebSocket PID $pid is alive"'
```

### Fast logical reset

This reset preserves the WebSocket process and skips graph export. It requires
`r2025b-wsfix1` or later:

```bash
RESET_SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

sudo k3s kubectl -n acram exec deployment/acram -- \
  touch /var/lib/acram/work/reset_acram_monitor.flag

sleep 5

sudo k3s kubectl -n acram exec deployment/acram -- sh -lc '
  test ! -e /var/lib/acram/work/reset_acram_monitor.flag
  /opt/acram/healthcheck.sh runtime
'

sudo k3s kubectl -n acram logs deployment/acram \
  --since-time="$RESET_SINCE" --timestamps
```

Expect `Risk monitor reset to initial stage.`, followed by new WebSocket
transactions. There must be no `callback context is not initialized` message
and no `Risk graph images exported` message after the reset.

## 7. Roll back if k3s startup fails

Stop the k3s copy before restoring Minikube:

```bash
sudo k3s kubectl -n acram scale deployment/acram --replicas=0
sudo k3s kubectl -n acram wait --for=delete pod \
  -l app.kubernetes.io/name=acram --timeout=180s || true
kubectl --context acram -n acram scale deployment/acram --replicas=1
kubectl --context acram -n acram rollout status deployment/acram --timeout=95m
```

The old Minikube PVC and image remain intact, so this rollback does not require
a rebuild.

The k3s PVC starts empty and ACRAM seeds its immutable runtime resources on
first startup. Historical generated plots and logs are not copied automatically;
they remain in the Minikube PVC for rollback or a later explicit data transfer.

## 8. Retire Minikube after validation

After k3s has processed live transactions successfully, stop the unused
Minikube cluster and its autostart service. Do not delete the profile until its
old PVC data is no longer needed.

```bash
minikube stop --profile acram
systemctl --user disable --now acram-minikube.service
```

The enabled `k3s-agent` service and Deployment desired state will restart ACRAM
after a host reboot; rootless Docker and the Minikube user service are no longer
needed for production ACRAM.
