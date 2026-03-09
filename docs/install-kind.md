# Install on Kind (Quick Validation)

This guide is for local validation and contributor testing. For real homelab usage, use `docs/install-k3s.md`.

## Prerequisites

- `kind`
- `kubectl`
- `terraform`
- `python3` + `pyyaml`
- `curl`, `jq`, `git`, `sed`
- Container runtime supported by Kind (`docker` or `podman`)
- Podman users: rootful machine mode
- Recommended system requirements: `6` CPUs and `12` GiB RAM

## 1) Prepare local config

From repo root:

```bash
cp config/homelab.kind.example.yaml config/homelab.yaml
```

You can keep defaults initially, but you must ensure the MetalLB range/VIPs are in the Kind network subnet.

## 2) Create the kind cluster

Use the provided cluster config (`disableDefaultCNI: true`) so Terraform-installed Cilium can take over networking.
The default config is single-node (control-plane only) to reduce local memory pressure.

### Docker

If you use Docker Desktop, set resources to at least `6` CPUs and `12` GiB RAM in Docker Desktop settings before creating the cluster.
You can check current Docker resources with:

```bash
docker info --format 'CPUs={{.NCPU}} TotalMemoryBytes={{.MemTotal}}'
```

```bash
kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0
kubectl config use-context kind-homelab
```

### Podman

For this Kind + Cilium path, use rootful Podman machine mode.

```bash
# Configure Podman machine once (or update existing defaults)
podman machine stop podman-machine-default
podman machine set --rootful=true --cpus 6 --memory 12288 podman-machine-default
podman machine start podman-machine-default

# Verify mode and resources
podman machine inspect podman-machine-default --format '{{.Rootful}} CPUs={{.Resources.CPUs}} MemoryMiB={{.Resources.Memory}}'
podman info --format 'rootless={{.Host.Security.Rootless}} cgroup={{.Host.CgroupsVersion}}'

# Create kind cluster with Podman provider
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0
kubectl config use-context kind-homelab
```

## 3) Choose MetalLB IPs from the kind network

Inspect the Kind network subnet:

```bash
# Docker
docker network inspect kind | jq -r '.[0].IPAM.Config[]?.Subnet | select(test("^[0-9]+(\\.[0-9]+){3}/[0-9]+$"))' | head -n1

# Podman
podman network inspect kind | jq -r '.[0].subnets[]?.subnet | select(test("^[0-9]+(\\.[0-9]+){3}/[0-9]+$"))' | head -n1
```

Pick an IP range and two VIPs inside that subnet, then edit `config/homelab.yaml`:

- `network.metallb_ip_range`
- `network.ingress_nginx_loadbalancer_ip`
- `network.gitea_ssh_loadbalancer_ip`

For Kind, keep:

- `storage.default_class: standard`

Optional:

- delete `network.gitea_ssh_allowed_sources` to allow SSH from all source ranges in local testing

## 4) Render bootstrap files

```bash
python3 scripts/render-config.py --config config/homelab.yaml
```

This updates:

- `bootstrap/ansible/inventory/hosts`
- `bootstrap/terraform/terraform.tfvars`
- rendered `platform-core/**/values.yaml` in your local workspace

## 5) Run Terraform bootstrap

Always pass context explicitly to avoid targeting a real cluster by mistake.

```bash
cd bootstrap/terraform
terraform init
terraform apply -var kubeconfig_context=kind-homelab -var kubeconfig_path=~/.kube/config
```

## 6) Verify platform health

```bash
kubectl get applications -n argocd
```

Expected steady state: all applications `Synced` and `Healthy`.

Check Gitea SSH VIP:

```bash
kubectl -n gitea get svc gitea-ssh -o wide
```

## 7) Access UIs (local)

Check ingress endpoints:

```bash
kubectl get ingress -A
```

If the ingress hostnames do not resolve locally, map them to the ingress VIP:

```bash
HOSTS=$(kubectl get ingress -A -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host}{" "}{end}{end}')
INGRESS_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$INGRESS_IP $HOSTS"
```

Add that output line to `/etc/hosts`.

Default UI/API endpoints from `config/homelab.kind.example.yaml`:

- ArgoCD: `https://cd.lab`
- Gitea: `https://git.lab`
- MinIO API (S3): `https://s3.lab`
- MinIO Console: `https://storage.lab`
- Vault UI: `https://secrets.lab`

Credential commands:

```bash
# ArgoCD
echo "username: admin"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# Gitea
kubectl -n gitea get secret gitea-admin -o jsonpath='{.data.username}' | base64 -d; echo
kubectl -n gitea get secret gitea-admin -o jsonpath='{.data.password}' | base64 -d; echo

# MinIO (console and S3)
kubectl -n minio get secret minio -o jsonpath='{.data.root-user}' | base64 -d; echo
kubectl -n minio get secret minio -o jsonpath='{.data.root-password}' | base64 -d; echo

# Vault (bootstrap root token)
kubectl -n vault get secret init-credentials -o jsonpath='{.data.root-token}' | base64 -d; echo
```

Port-forward fallback for ArgoCD:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Open `http://localhost:8080`.

## 8) Teardown

```bash
# Docker
kind delete cluster --name homelab

# Podman
KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name homelab
```

## Troubleshooting: Cilium Init errors on Podman

Symptom pattern:

- Cilium pods show `Init:Error` or `Init:CrashLoopBackOff`
- Cilium init container `mount-bpf-fs` reports `mount: /sys/fs/bpf: permission denied`
- Most workloads stay `Pending` because nodes remain tainted with `node.cilium.io/agent-not-ready`

Quick diagnosis:

```bash
kubectl -n cilium get pods -o wide
kubectl -n cilium describe pod $(kubectl -n cilium get pod -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.taints[*]}{.key}{":"}{.effect}{";"}{end}{"\n"}{end}'
```

Important: `sudo podman ...` does not change Podman machine mode.

Use a rootful Podman machine for this Kind + Cilium path:

```bash
podman machine stop podman-machine-default
podman machine set --rootful=true --cpus 6 --memory 12288 podman-machine-default
podman machine start podman-machine-default

podman machine inspect podman-machine-default --format '{{.Rootful}} CPUs={{.Resources.CPUs}} MemoryMiB={{.Resources.Memory}}'
podman info --format 'rootless={{.Host.Security.Rootless}} cgroup={{.Host.CgroupsVersion}}'
```

Recreate Kind and verify bpffs mount inside all Kind node containers before Terraform:

```bash
KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name homelab
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0
kubectl config use-context kind-homelab

for n in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}'); do
  echo "== $n =="
  podman exec "$n" sh -c 'mount | grep -q " /sys/fs/bpf type bpf " || mount -t bpf bpf /sys/fs/bpf'
done

for n in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}'); do
  echo "== $n =="
  podman exec "$n" sh -c 'mount | grep "/sys/fs/bpf type bpf"'
done
```

If each node shows `/sys/fs/bpf type bpf`, rerun:

```bash
cd bootstrap/terraform
terraform apply -var kubeconfig_context=kind-homelab -var kubeconfig_path=~/.kube/config
```
