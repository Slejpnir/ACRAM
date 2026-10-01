# ACRAM Nokia Kubernetes deployment from Linux

This guide deploys the Nokia 2025 ACRAM profile from an Ubuntu 24.04
`amd64` host. It supports either a local Minikube cluster or an existing
Kubernetes cluster.

The repository deliberately does not contain ADI credentials. Keep
`ws_credentials_nokia.json` outside Git and never bake it into the image.

## 1. Host requirements

Use a machine with:

- Linux `amd64` (Ubuntu 24.04 is the tested target);
- Docker Engine 20.10 or newer;
- at least 4 CPU cores, 10 GiB free RAM, and 40 GiB free disk;
- Internet access to Docker Hub, MathWorks registries, and the Nokia ADI
  WebSocket endpoint;
- a MathWorks license valid for R2025b, MATLAB Compiler, Control System
  Toolbox, Fuzzy Logic Toolbox, and Instrument Control Toolbox;
- `ws_credentials_nokia.json` with the fields `user_id`, `private_key`,
  `public_key`, `websocket_address`, `context_id_component`, and
  `context_id_aggregated`.

Verify Docker before continuing:

```bash
docker info --format '{{.OSType}}/{{.Architecture}} {{.ServerVersion}}'
```

The output must start with `linux/x86_64` or `linux/amd64`.

## 2. Obtain the source and credentials

```bash
git clone <your-repository-url> TELEMETRY
cd TELEMETRY
```

Copy the Nokia credential file into the repository root only for the
deployment command:

```bash
install -m 600 /secure/path/ws_credentials_nokia.json \
  ./ws_credentials_nokia.json
```

The filename is ignored by Git. Confirm that it is not tracked:

```bash
git check-ignore ws_credentials_nokia.json
```

Do not print the file or commit it.

## 3. Build the Linux standalone executable

MATLAB Compiler output is platform-specific. A Windows `ACRAM.exe` cannot
run in the Linux runtime image.

### Option A: MATLAB R2025b is installed on Linux

From the repository root:

```bash
matlab -batch "build_kubernetes('dist/bin')"
test -x dist/bin/ACRAM
file dist/bin/ACRAM
```

`file` must report a Linux ELF executable or launcher, not PE32/Windows.

### Option B: build through the official MATLAB browser container

Use this route when Docker is installed but MATLAB is not installed on the
Linux host. Individual and Campus-Wide licenses normally support MathWorks
browser licensing; other license types may require a network license server.

Build a browser-enabled R2025b compiler image from the official MathWorks
Dockerfile:

```bash
git clone --depth 1 \
  https://github.com/mathworks-ref-arch/matlab-dockerfile.git \
  /tmp/matlab-dockerfile

docker build \
  --file /tmp/matlab-dockerfile/alternates/building-on-matlab-docker-image/Dockerfile \
  --build-arg MATLAB_RELEASE=R2025b \
  --build-arg 'ADDITIONAL_PRODUCTS=MATLAB_Compiler Control_System_Toolbox Fuzzy_Logic_Toolbox Instrument_Control_Toolbox' \
  --build-arg 'FONTS_PACKAGES=' \
  --tag acram-matlab-builder:r2025b \
  /tmp/matlab-dockerfile/alternates/building-on-matlab-docker-image
```

Start the compiler on the loopback interface. The startup command compiles
ACRAM automatically after MATLAB authorization succeeds:

```bash
docker run --name acram-matlab-compiler --init --shm-size=1g \
  --publish 127.0.0.1:8888:8888 \
  --volume "$PWD:/workspace" \
  --env "MWI_MATLAB_STARTUP_SCRIPT=cd('/workspace'); build_kubernetes('/workspace/dist/bin')" \
  acram-matlab-builder:r2025b -browser
```

Open `http://localhost:8888`, sign in with the MathWorks account linked to
the license, and wait for compilation to finish. In another terminal:

```bash
until test -x dist/bin/ACRAM; do sleep 5; done
file dist/bin/ACRAM
```

If the browser reports `MATLABCustomStartupCodeError`, inspect that variable
in the MATLAB workspace. Stop and remove the temporary compiler container
after `dist/bin/ACRAM` exists:

```bash
docker stop acram-matlab-compiler
docker rm acram-matlab-compiler
```

For a network license manager, build with the same image and run MATLAB in
batch mode instead:

```bash
docker run --rm --init --shm-size=1g \
  --env MLM_LICENSE_FILE=27000@license-server.example.com \
  --volume "$PWD:/workspace" \
  --workdir /workspace \
  acram-matlab-builder:r2025b \
  -batch "build_kubernetes('/workspace/dist/bin')"
```

Replace the example server address with the value supplied by the license
administrator. Do not place license credentials in the image.

## 4. Build the runtime image

The compiler and MATLAB Runtime releases must match:

```bash
docker build \
  --build-arg MATLAB_RUNTIME_TAG=r2025b-full \
  --build-arg MATLAB_RELEASE=R2025b \
  --tag registry.example.com/telemetry/acram:r2025b \
  .
```

Confirm the image is Linux `amd64`:

```bash
docker image inspect registry.example.com/telemetry/acram:r2025b \
  --format '{{.Os}}/{{.Architecture}} {{.Id}}'
```

The image contains the compiled program and non-secret Nokia model assets.
It does not contain `ws_credentials_nokia.json`.

## 5A. Create a local Minikube cluster

Skip this section when deploying to an existing cluster.

Install the current Minikube binary:

```bash
curl -LO \
  https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
```

Start a dedicated profile:

```bash
minikube start --profile=acram --driver=docker \
  --container-runtime=containerd \
  --cpus=4 --memory=10240mb --disk-size=40g
```

Use its context explicitly and load the local image:

```bash
kubectl --context acram get nodes
minikube --profile acram image load \
  registry.example.com/telemetry/acram:r2025b
```

Keep `imagePullPolicy: IfNotPresent`; Kubernetes will use the image loaded
into Minikube.

## 5B. Use an existing Kubernetes cluster

Confirm the target before changing it:

```bash
kubectl config get-contexts
kubectl config current-context
kubectl cluster-info
```

Authenticate to a registry, tag and push the image, then update
`k8s/kustomization.yaml` with that registry and immutable tag:

```bash
docker tag registry.example.com/telemetry/acram:r2025b \
  REGISTRY/PROJECT/acram:r2025b
docker push REGISTRY/PROJECT/acram:r2025b
```

For a private registry, create an `imagePullSecret` and reference it from
the pod specification. Do not deploy while the active context is ambiguous.

## 6. Create the Nokia Secret

The following commands use context `acram`. Replace it with the verified
production context when using an existing cluster.

```bash
kubectl --context acram apply -f k8s/namespace.yaml

kubectl --context acram --namespace acram \
  create secret generic acram-adi-credentials \
  --from-file=credentials.json=./ws_credentials_nokia.json \
  --dry-run=client --output=yaml |
kubectl --context acram apply -f -
```

Optionally add an NVD API key without putting it in a manifest:

```bash
read -rsp 'NVD API key: ' NVD_API_KEY
printf '\n'
kubectl --context acram --namespace acram \
  create secret generic acram-adi-credentials \
  --from-file=credentials.json=./ws_credentials_nokia.json \
  --from-literal=nvd-api-key="$NVD_API_KEY" \
  --dry-run=client --output=yaml |
kubectl --context acram apply -f -
unset NVD_API_KEY
```

## 7. Deploy the Nokia profile

Render first, then apply:

```bash
kubectl kustomize k8s >/tmp/acram-rendered.yaml
kubectl --context acram apply -f /tmp/acram-rendered.yaml
kubectl --context acram --namespace acram \
  rollout status deployment/acram --timeout=10m
```

The checked-in ConfigMap selects `k8s/config/config.json`, which is the Nokia
2025 configuration with GUI disabled. The Deployment runs one replica using
the `Recreate` strategy to avoid duplicate ADI publishers.

## 8. Verify operation

```bash
kubectl --context acram --namespace acram get pods,pvc
kubectl --context acram --namespace acram \
  describe pod --selector app.kubernetes.io/name=acram
kubectl --context acram --namespace acram \
  logs deployment/acram --follow
```

Expected state:

- the PVC `acram-data` is `Bound`;
- one ACRAM pod is `Running` and `Ready`;
- the startup log reaches `[entrypoint] launching ACRAM`;
- `/tmp/acram/ready` exists;
- the WebSocket helper PID referenced by
  `/var/lib/acram/work/smartqc_pid.txt` is alive.

Inspect generated output without exposing the Secret:

```bash
kubectl --context acram --namespace acram exec deployment/acram -- \
  sh -c 'find /var/lib/acram/work -maxdepth 2 -type f -printf "%p %s bytes\n" | sort'
```

Copy results to the Linux host:

```bash
pod="$(kubectl --context acram --namespace acram \
  get pod --selector app.kubernetes.io/name=acram \
  --output=jsonpath='{.items[0].metadata.name}')"
kubectl --context acram --namespace acram \
  cp "$pod:/var/lib/acram/work" ./acram-results
```

## 9. Troubleshooting

### `ImagePullBackOff`

For Minikube, confirm the exact tag is loaded:

```bash
minikube --profile acram image ls | grep acram
```

For a real cluster, confirm the image was pushed and its pull secret is
attached.

### Pod is running but not ready

Readiness requires both the MATLAB ready marker and a live ADI WebSocket
process:

```bash
kubectl --context acram --namespace acram logs deployment/acram
kubectl --context acram --namespace acram exec deployment/acram -- \
  sh -c 'ls -l /tmp/acram/ready /var/lib/acram/work/smartqc_pid.txt'
```

Check that the cluster can reach the `websocket_address` in the Nokia
credential file and that any required VPN or firewall route is active.

### `CrashLoopBackOff`

```bash
kubectl --context acram --namespace acram \
  logs deployment/acram --previous
kubectl --context acram --namespace acram \
  get events --sort-by=.lastTimestamp
```

Common causes are a missing executable, mismatched R2025b Runtime, malformed
credentials, or insufficient memory.

### PVC remains pending

```bash
kubectl --context acram get storageclass
kubectl --context acram --namespace acram describe pvc acram-data
```

The cluster needs a default storage class supporting `ReadWriteOnce`.

## 10. Stop or remove the deployment

Stop the workload but preserve its PVC and results:

```bash
kubectl --context acram --namespace acram delete deployment acram
```

Remove the local Minikube profile only after copying required results:

```bash
minikube stop --profile acram
minikube delete --profile acram
```

Deleting the profile destroys its local PVC data.
