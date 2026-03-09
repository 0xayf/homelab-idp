<p align="center">
  <img src="assets/logo.png" alt="Homelab IDP" width="400">
  <br>
  <em>A self-managing internal developer platform for your homelab.</em>
</p>

## Overview

Homelab IDP bootstraps a Kubernetes platform, seeds GitOps state into Gitea, then hands ongoing ownership to ArgoCD.

- **Bootstrap layer**: Ansible + Terraform create the initial cluster state.
- **GitOps handoff**: Bootstrap script pushes `platform-core` into Gitea and applies the ArgoCD `ApplicationSet`.
- **Day-2 model**: All future platform changes happen in `homelab/platform-core` (inside Gitea), managed by ArgoCD.

## What Gets Installed

Core platform services managed by ArgoCD from `platform-core/`:

- Core: ArgoCD, Cilium, Gitea, ingress-nginx, MetalLB, cert-manager
- Security: Vault, External Secrets
- Storage: MinIO, CloudNativePG
- Control plane: Crossplane, Crossplane compositions

For deeper bootstrap internals, see `docs/terraform-bootstrap-handoff.md`.

## Quick Start (Kind)

Use this path to validate the platform quickly on a local disposable cluster.
The provided Kind config is single-node (control-plane only) to reduce local resource usage.

Prerequisites:

- `kind`, `kubectl`, `terraform`
- `python3` + `pyyaml`
- `curl`, `jq`, `git`, `sed`
- container runtime for Kind:
  - Docker
  - Podman (rootful machine mode for this Kind + Cilium path)
- Recommended resource requirements: `6` CPUs, `12` GiB RAM

If you use Docker Desktop, set resources in Docker Desktop settings before cluster creation.
You can check current Docker resources with:
`docker info --format 'CPUs={{.NCPU}} TotalMemoryBytes={{.MemTotal}}'`

```bash
# 1) Create local config from the kind profile
cp config/homelab.kind.example.yaml config/homelab.yaml

# 2) Podman only: set rootful mode + recommended resources
podman machine stop podman-machine-default
podman machine set --rootful=true --cpus 6 --memory 12288 podman-machine-default
podman machine start podman-machine-default

# 3) Create the kind cluster
# Docker
kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0

# Podman (rootful)
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0

kubectl config use-context kind-homelab

# 4) Confirm your kind network subnet and adjust config/homelab.yaml VIPs if needed
# Docker:
docker network inspect kind | jq -r '.[0].IPAM.Config[]?.Subnet | select(test("^[0-9]+(\\.[0-9]+){3}/[0-9]+$"))' | head -n1
# Podman:
podman network inspect kind | jq -r '.[0].subnets[]?.subnet | select(test("^[0-9]+(\\.[0-9]+){3}/[0-9]+$"))' | head -n1

# 5) Render config into tfvars/inventory/platform-core values
python3 scripts/render-config.py --config config/homelab.yaml

# 6) Bootstrap platform
cd bootstrap/terraform
terraform init
terraform apply -var kubeconfig_context=kind-homelab -var kubeconfig_path=~/.kube/config

# 7) Verify
kubectl get applications -n argocd
```

Quick local UI access (default hosts from `config/homelab.kind.example.yaml`):

- ArgoCD: `https://cd.lab`
- Gitea: `https://git.lab`
- MinIO Console: `https://storage.lab`
- MinIO API (S3): `https://s3.lab`
- Vault: `https://secrets.lab`

If those hostnames do not resolve, print a hosts entry and add it to `/etc/hosts`:

```bash
HOSTS=$(kubectl get ingress -A -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host}{" "}{end}{end}')
INGRESS_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$INGRESS_IP $HOSTS"
```

Initial credentials:

```bash
# ArgoCD
echo "username: admin"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# Gitea
kubectl -n gitea get secret gitea-admin -o jsonpath='{.data.username}' | base64 -d; echo
kubectl -n gitea get secret gitea-admin -o jsonpath='{.data.password}' | base64 -d; echo

# MinIO
kubectl -n minio get secret minio -o jsonpath='{.data.root-user}' | base64 -d; echo
kubectl -n minio get secret minio -o jsonpath='{.data.root-password}' | base64 -d; echo

# Vault
kubectl -n vault get secret init-credentials -o jsonpath='{.data.root-token}' | base64 -d; echo
```

Full local runbook (including Podman/WSL notes, UI access, cleanup):
`docs/install-kind.md`

## Recommended Deployment (k3s)

For long-lived homelab use, install onto a real host with k3s:

1. Copy `config/homelab.k3s.example.yaml` to `config/homelab.yaml`
2. Render config with `scripts/render-config.py`
3. Provision k3s with Ansible
4. Run Terraform bootstrap
5. Configure DNS + trust cluster CA

Start here: `docs/install-k3s.md`

## Configuration Profiles

Use one of the provided templates as your starting point:

- `config/homelab.kind.example.yaml` - local Kind profile (`storage.default_class: standard`)
- `config/homelab.k3s.example.yaml` - real k3s profile (`storage.default_class: local-path`)

Full config reference: `docs/configuration.md`

## Post-Bootstrap Workflow

After bootstrap succeeds:

- Clone `homelab/platform-core` from your Gitea instance
- Edit Helm chart values or add chart directories
- Push changes to Gitea
- ArgoCD reconciles automatically

## Documentation Map

- `docs/install-kind.md` - local Kind install and verification
- `docs/install-k3s.md` - recommended real deployment path
- `docs/configuration.md` - `homelab.yaml` schema, defaults, environment profiles
- `docs/ansible-k3s-provisioning.md` - detailed Ansible playbooks and role vars
- `docs/terraform-bootstrap-handoff.md` - Terraform bootstrap and ArgoCD takeover internals
- `docs/secrets-management.md` - Vault/ESO/Crossplane architecture
