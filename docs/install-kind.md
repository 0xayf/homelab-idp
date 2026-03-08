# Install on Kind (Quick Validation)

This guide is for local validation and contributor testing. For real homelab usage, use `docs/install-k3s.md`.

## Prerequisites

- `kind`
- `kubectl`
- `terraform`
- `python3` + `pyyaml`
- `curl`, `jq`, `git`, `sed`
- Container runtime supported by Kind (`docker` or `podman`)

## 1) Prepare local config

From repo root:

```bash
cp config/homelab.kind.example.yaml config/homelab.yaml
```

You can keep defaults initially, but you must ensure the MetalLB range/VIPs are in the Kind network subnet.

## 2) Create the kind cluster

Use the provided cluster config (`disableDefaultCNI: true`) so Terraform-installed Cilium can take over networking.

### Docker

```bash
kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0
kubectl config use-context kind-homelab
```

### Podman

Rootless podman may require cgroup delegation. If rootless does not work in your environment, use rootful podman.

```bash
# Rootless example
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0

# Rootful fallback
sudo env KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0
```

If you used rootful podman, merge the generated kubeconfig into your user config:

```bash
mkdir -p ~/.kube
sudo kind get kubeconfig --name homelab > ~/.kube/kind-homelab.config
KUBECONFIG="$HOME/.kube/config:$HOME/.kube/kind-homelab.config"
kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config
kubectl config use-context kind-homelab
```

## 3) Choose MetalLB IPs from the kind network

Inspect the Kind network subnet:

```bash
# Docker
docker network inspect kind --format '{{(index .IPAM.Config 0).Subnet}}'

# Podman
podman network inspect kind | jq -r '.[0].subnets[0].subnet'
```

If you created Kind with rootful podman, run podman network commands with `sudo`.

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

ArgoCD UI via port-forward:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Open `http://localhost:8080`.

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

## 8) Teardown

```bash
# Docker
kind delete cluster --name homelab

# Podman
KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name homelab
# or rootful:
sudo env KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name homelab
```
