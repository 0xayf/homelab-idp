<p align="center">
  <img src="assets/logo.png" alt="Homelab IDP" width="400">
  <br>
  <em>A self-managing internal developer platform for your homelab.</em>
</p>

## Overview

Homelab IDP bootstraps a Kubernetes platform, seeds GitOps state into Gitea, then hands ongoing ownership to ArgoCD.

- **Bootstrap layer**: Ansible + Terraform create the initial cluster state.
- **GitOps handoff**: Bootstrap script pushes `platform-core` into Gitea and applies the ArgoCD `ApplicationSet`.
- **Day-2 model**: all future platform changes happen in `homelab/platform-core` (inside Gitea), not in Terraform.

## What Gets Installed

Core platform services managed by ArgoCD from `platform-core/`:

- Core: ArgoCD, Cilium, Gitea, ingress-nginx, MetalLB, cert-manager
- Security: Vault, External Secrets
- Storage: MinIO, CloudNativePG
- Control plane: Crossplane, Crossplane compositions

For deeper bootstrap internals, see `docs/terraform-bootstrap-handoff.md`.

## Quick Start (Kind)

Use this path to validate the platform quickly on a local disposable cluster.

Prerequisites:

- `kind`, `kubectl`, `terraform`
- `python3` + `pyyaml`
- `curl`, `jq`, `git`, `sed`
- container runtime for Kind (Docker or Podman)

```bash
# 1) Create local config from the kind profile
cp config/homelab.kind.example.yaml config/homelab.yaml

# 2) Create the kind cluster
kind create cluster --name homelab --config docs/examples/kind-homelab.yaml --wait 0
kubectl config use-context kind-homelab

# 3) Confirm your kind network subnet and adjust config/homelab.yaml VIPs if needed
# Docker:
docker network inspect kind --format '{{(index .IPAM.Config 0).Subnet}}'
# Podman:
podman network inspect kind | jq -r '.[0].subnets[0].subnet'

# 4) Render config into tfvars/inventory/platform-core values
python3 scripts/render-config.py --config config/homelab.yaml

# 5) Bootstrap platform
cd bootstrap/terraform
terraform init
terraform apply -var kubeconfig_context=kind-homelab -var kubeconfig_path=~/.kube/config

# 6) Verify
kubectl get applications -n argocd
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
- `docs/troubleshooting.md` - common bootstrap/runtime issues and fixes
- `docs/ansible-k3s-provisioning.md` - detailed Ansible playbooks and role vars
- `docs/terraform-bootstrap-handoff.md` - Terraform bootstrap and ArgoCD takeover internals
- `docs/secrets-management.md` - Vault/ESO/Crossplane architecture
