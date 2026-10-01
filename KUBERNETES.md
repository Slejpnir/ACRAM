# Running ACRAM on Kubernetes

For deployment into the shared k3s cluster on Nokia host `uc2-3`, use the
dedicated overlay and cutover procedure in `K3S_UC2_3.md`. A Minikube profile
is a separate cluster and will not appear in the shared k3s console.

This repository contains a Kubernetes package for the Nokia 2025 ADI profile.
The pod runs one compiled MATLAB process, maintains one ADI WebSocket
connection, and stores generated output on a persistent volume.

## Prerequisites

- A Linux `amd64` build machine with MATLAB R2025b and MATLAB Compiler.
- The MATLAB products required by ACRAM, including Fuzzy Logic Toolbox and
  Instrument Control Toolbox.
- Docker or another OCI image builder.
- A Kubernetes cluster with a default `ReadWriteOnce` storage class.
- An ADI credentials JSON file matching `ws_credentials.example.json`.

MATLAB Compiler output is platform-specific. The existing Windows executable
cannot run in this Linux image. The MATLAB Runtime release must also match the
MATLAB release used to compile the application.

## 1. Build the Linux application

Run this from the repository root on the Linux MATLAB build machine:

```bash
matlab -batch "build_kubernetes('dist/bin')"
```

The Docker build deliberately fails if `dist/bin/ACRAM` is absent. The
generated binary is ignored by Git through `dist/.gitignore`.

The Kubernetes-specific entry point is `acram_k8s_main.m`. It keeps the
compiled process alive after the initial risk calculation so MATLAB timers can
service ADI WebSocket messages. It also owns readiness and shutdown markers.

## 2. Build and push the image

The default image uses the full R2025b MATLAB Runtime because ACRAM exports
graphs:

```bash
docker build \
  --build-arg MATLAB_RUNTIME_TAG=r2025b-full \
  --build-arg MATLAB_RELEASE=R2025b \
  -t registry.example.com/telemetry/acram:r2025b .

docker push registry.example.com/telemetry/acram:r2025b
```

For a different MATLAB release, change both build arguments and compile with
that same release. Pin the tested base image by digest in production.

The Docker context is an allow-list. It includes only the Linux executable,
model/data assets, non-secret configuration, and the two Python packages.
Credential files, VPN files, old Windows builds, generated output, and source
files such as `main.m` are excluded.

## 3. Configure the Kubernetes image

Edit `k8s/kustomization.yaml`:

```yaml
images:
  - name: acram
    newName: registry.example.com/telemetry/acram
    newTag: r2025b
```

The default Kubernetes scenario is in `k8s/config/config.json`. It is a
copy of `config_Nokia_robot_CVE_2025.json`; ACRAM forces its GUI off on Linux. If its
`credentialsFileName` changes, set `ACRAM_CREDENTIALS_FILENAME` in
`k8s/deployment.yaml` to the same filename.

Do not put credentials in the ConfigMap or container image.

## 4. Create the Secret

Create the namespace first:

```bash
kubectl apply -f k8s/namespace.yaml
```

Create the Secret directly from the real local JSON file:

```bash
kubectl create secret generic acram-adi-credentials \
  --namespace acram \
  --from-file=credentials.json=/secure/path/ws_credentials_nokia.json \
  --dry-run=client -o yaml \
  | kubectl apply -f -
```

`k8s/secret.example.yaml` documents the expected shape but contains
placeholders and is intentionally not included by Kustomize.

## 5. Deploy

```bash
kubectl apply -k k8s
kubectl rollout status deployment/acram -n acram --timeout=10m
kubectl logs -n acram deployment/acram --follow
```

Inspect readiness and persisted results with:

```bash
kubectl get pods -n acram
kubectl describe pod -n acram -l app.kubernetes.io/name=acram
kubectl exec -n acram deployment/acram -- ls -la /var/lib/acram/work
```

Delete the workload without deleting its results:

```bash
kubectl delete deployment acram -n acram
```

The PVC remains until it is explicitly deleted.

### Fast logical reset

Fast reset requires image `r2025b-wsfix1` or later. Earlier images can lose the
ADI callback context during reset and then ignore subsequent WebSocket
transactions.

Keep `exportRiskGraphs` enabled when graphs should be generated during a cold
application start and live risk updates. To reset ACRAM's in-memory risk and
transaction state without recreating the pod or exporting graph images, create
the reset request file in the running container:

```bash
kubectl --context acram -n acram exec deployment/acram -- \
  touch /var/lib/acram/work/reset_acram_monitor.flag

kubectl --context acram -n acram logs -f deployment/acram \
  --since=30s --timestamps
```

The monitor consumes and removes the request file. Expect `Risk monitor reset
to initial stage.` in the log. This logical reset keeps the existing WebSocket
session and does not run the cold-start data preparation or graph-image export.
Use `kubectl rollout restart` only when a full process restart is required.

After the reset, verify that the request was consumed and the WebSocket helper
is still healthy:

```bash
kubectl --context acram -n acram exec deployment/acram -- sh -lc '
  test ! -e /var/lib/acram/work/reset_acram_monitor.flag
  /opt/acram/healthcheck.sh runtime
'

kubectl --context acram -n acram logs deployment/acram \
  --since=2m --timestamps |
  grep -E 'Risk monitor reset|Transaction received|callback context is not initialized|Risk graph images exported'
```

New transactions should follow the reset. The two error cases in that final
pattern (`callback context is not initialized` and graph export) must not appear.

## Runtime behavior

- Exactly one replica is used. ACRAM keeps risk, WebSocket, and job state in
  memory and writes local files without cross-pod coordination.
- `Recreate` prevents an old and a new pod from publishing duplicate results
  during rollout.
- `/var/lib/acram` is the PVC mount. ACRAM uses its user-owned `work`
  subdirectory, `/var/lib/acram/work`, for generated JSON, CSV, graphs, logs,
  WebSocket files, and runtime assets.
- MATLAB Runtime cache and `/tmp` use bounded ephemeral volumes.
- The root filesystem is read-only and the process runs as UID/GID `10001`.
- The startup probe allows up to five minutes for MATLAB Runtime and initial
  risk evaluation.
- Readiness requires both the MATLAB ready marker and a live WebSocket Python
  process. No liveness probe is used; an authentication or network failure
  makes the pod visibly unready without causing an aggressive restart loop.
- Pod termination creates the stop marker, allows MATLAB cleanup to run, and
  then terminates any remaining WebSocket child.

## Other scenarios and aggregator mode

The image includes the tracked Telco, Nokia, and Antonov configuration/data files, and
the supplied Kubernetes ConfigMap selects Nokia 2025.

To switch to Telco 3PC, replace `k8s/config/config.json` and change
`ACRAM_CREDENTIALS_FILENAME` to `ws_credentials_tim.json`.

Antonov additionally references `Antonov_sbom.json`, which is intentionally
not tracked. Supply it through a separate read-only volume or a controlled
artifact source before selecting that configuration.

Port `5600` is opened only by `realTimeMode: "aggregator"`. The checked-in
Kubernetes profile uses ADI mode and therefore has no Service. The legacy
aggregator configuration is not currently valid against the enhanced entry
point, so an aggregator Service is intentionally not shipped as if it were
ready. Once a validated aggregator config exists:

1. set `ACRAM_HEALTH_MODE=marker`;
2. add a `ClusterIP` Service for TCP port `5600`;
3. restrict callers with a NetworkPolicy because `/evaluate` and `/reset`
   currently have no application-level authentication.

## References

- [MathWorks MATLAB Runtime containers](https://www.mathworks.com/help/compiler/get-matlab-runtime-container.html)
- [Create standalone applications](https://www.mathworks.com/help/compiler/compiler.build.standaloneapplication.html)
- [MATLAB and Python version compatibility](https://www.mathworks.com/support/requirements/python-compatibility.html)
