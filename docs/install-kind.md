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

```bash
kind create cluster --config docs/examples/kind-homelab.yaml --wait 0
kubectl config use-context kind-homelab
```

### Podman

For this Kind + Cilium path, use rootful Podman machine mode.

```bash
# Configure Podman machine once (or update existing defaults)
podman machine stop podman-machine-default
podman machine set --rootful=true --cpus 6 --memory 12288 podman-machine-default
podman machine start podman-machine-default

# Create kind cluster
kind create cluster --config docs/examples/kind-homelab.yaml --wait 0
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
- `network.traefik_loadbalancer_ip`
- `network.gitea_ssh_loadbalancer_ip`

For Kind, keep:

- `storage.default_class: standard`

Optional:

- Delete `network.gitea_ssh_allowed_sources` to allow SSH from all sources in local testing
- Delete `network.traefik_dashboard_allowed_sources` to allow dashboard access from all sources

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

## 6) Patch CoreDNS (recommended)

Services like the Gitea Actions runner need to resolve `*.local.lab` hostnames inside the cluster. Run the provided script to add DNS entries pointing to the Traefik LoadBalancer IP:

```bash
bash docs/examples/kind-patch-dns.sh
```

This is only needed for Kind — on a real k3s cluster, your network DNS handles resolution.

## 7) Verify platform health

```bash
kubectl get applications -n argocd
```

Expected steady state: all applications `Synced` and `Healthy`.

## 8) Access UIs

With Kind + Podman, MetalLB IPs are not routable from the host. Use port-forwards:

```bash
# ArgoCD UI (username: admin)
kubectl port-forward svc/argocd-server -n argocd 8080:80
# -> http://localhost:8080

# Gitea (username: admin)
kubectl port-forward svc/gitea-http -n gitea 3000:3000
# -> http://localhost:3000

# RustFS Console (S3-compatible object storage)
kubectl port-forward svc/rustfs-svc -n rustfs 9001:9001
# -> http://localhost:9001

# Vault UI
kubectl port-forward svc/vault -n vault 8200:8200
# -> http://localhost:8200
```

With Kind + Docker (MetalLB IPs may be routable), add hosts entries:

```bash
TRAEFIK_IP=$(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$TRAEFIK_IP auth.local.lab cd.local.lab git.local.lab gateway.local.lab storage.local.lab s3.local.lab secrets.local.lab"
```

Add that line to `/etc/hosts`, then access services at their `*.local.lab` hostnames.

## 9) Credentials

```bash
# ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# Gitea
kubectl -n gitea get secret gitea-admin -o jsonpath='{.data.password}' | base64 -d; echo

# RustFS
kubectl -n rustfs get secret rustfs-root-credentials -o jsonpath='{.data.RUSTFS_ACCESS_KEY}' | base64 -d; echo
kubectl -n rustfs get secret rustfs-root-credentials -o jsonpath='{.data.RUSTFS_SECRET_KEY}' | base64 -d; echo

# Vault
kubectl -n vault get secret init-credentials -o jsonpath='{.data.root-token}' | base64 -d; echo

# Keycloak lab-admin (created by Crossplane after bootstrap)
kubectl -n keycloak get secret lab-admin -o jsonpath='{.data.password}' | base64 -d; echo
```

## 10) Teardown

```bash
kind delete cluster --name homelab
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

Use a rootful Podman machine for this Kind + Cilium path:

```bash
podman machine stop podman-machine-default
podman machine set --rootful=true --cpus 6 --memory 12288 podman-machine-default
podman machine start podman-machine-default
```

Recreate Kind and verify bpffs mount inside all Kind node containers before Terraform:

```bash
kind delete cluster --name homelab
kind create cluster --config docs/examples/kind-homelab.yaml --wait 0
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
