<p align="center">
  <img src="assets/logo.png" alt="Homelab IDP" width="400">
  <br>
  <em>A self-managing internal developer platform for your homelab.</em>
</p>

## Overview

This repository bootstraps an IDP and then hands ongoing management to GitOps workflows:

- **Ansible** provisions a single-node k3s cluster on your target server
- **Terraform** deploys core platform services and runs a one-time bootstrap script
- **Bootstrap script** creates a Gitea repo, pushes Helm charts, and wires ArgoCD to Gitea
- **ArgoCD** takes over and manages **all** platform applications (including Cilium, Gitea, and ArgoCD itself) via GitOps

After bootstrap completes you have a fully self-managing platform. This repository is never used again — all ongoing changes are made through `platform-core` in Gitea.

## Architecture

### Bootstrap Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                LOCAL MACHINE                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐      ┌──────────────┐      ┌────────────────────────────┐  │
│  │  1. Config   │      │  2. Ansible  │      │       3. Terraform         │  │
│  │              │      │              │      │                            │  │
│  │ homelab.yml  │─────>│  Provision   │─────>│  Deploy Cilium, Gitea,     │  │
│  │      +       │      │ k3s cluster  │      │  ArgoCD via Helm           │  │
│  │   render-    │      │              │      │                            │  │
│  │  config.py   │      └──────────────┘      │  Run bootstrap.sh via      │  │
│  └──────────────┘              │             │  local-exec (port-forward  │  │
│         │                      │             │  to Gitea on localhost)    │  │
│         │                      │             └────────────────────────────┘  │
│         │                      │                          │                  │
│         v                      │                          │                  │
│  Patches platform-core         │                          │                  │
│  values.yaml files with        │                          │                  │
│  hostnames and IPs             │                          │                  │
│                                │                          │                  │
└────────────────────────────────│──────────────────────────│──────────────────┘
                                 │                          │
                                 v                          v
┌──────────────────────────────────────────────────────────────────────────────┐
│                                K3S CLUSTER                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                 TERRAFORM DEPLOYS (Helm releases)                      │  │
│  │     ┌──────────┐             ┌──────────┐             ┌──────────┐     │  │
│  │     │  Cilium  │             │  Gitea   │             │  ArgoCD  │     │  │
│  │     │   (CNI)  │             │  (Git)   │             │   (CD)   │     │  │
│  │     └──────────┘             └──────────┘             └──────────┘     │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                        │
│  ┌──────────────────────────────────│─────────────────────────────────────┐  │
│  │         BOOTSTRAP SCRIPT         │     (runs on local machine via      │  │
│  │                                  │      kubectl port-forward)          │  │
│  │  1. Create Gitea org + bot user  │                                     │  │
│  │  2. Create platform-core repo   <┘                                     │  │
│  │  3. Push Helm charts to Gitea                                          │  │
│  │  4. Create argocd-repositories secret                                  │  │
│  │  5. Apply ArgoCD ApplicationSet                                        │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                        │
│                                     v                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │               ARGOCD-MANAGED (all apps, including core)                │  │
│  │                                                                        │  │
│  │  core/               controlplane/                security/            │  │
│  │  ├─ argocd           ├─ crossplane                ├─ vault             │  │
│  │  ├─ gitea            └─ crossplane-composition    └─ external-secrets  │  │
│  │  ├─ cilium                                                             │  │
│  │  ├─ cert-manager     storage/                                          │  │
│  │  ├─ ingress-nginx    ├─ minio                                          │  │
│  │  └─ metallb          └─ cloudnative-pg                                 │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Post-Bootstrap Ownership

After bootstrap completes:

- `homelab/platform-core` in Gitea is the single source of truth for the platform
- ArgoCD manages **all** platform components from that repo, including Cilium, Gitea, and ArgoCD itself
- Every `Chart.yaml` in `platform-core` is discovered by the ApplicationSet and reconciled continuously
- Terraform in this repo is bootstrap-only and is not used for day-2 operations

For details on how the bootstrap module works, see [docs/terraform-bootstrap-handoff.md](docs/terraform-bootstrap-handoff.md).

## Prerequisites

- Python 3 with PyYAML (`pip install pyyaml`)
- Ansible (`pip install ansible`)
- Terraform (runs the bootstrap `local-exec` script)
- kubectl
- jq, curl, git, sed (required by bootstrap `local-exec`)
- A target server running Ubuntu with SSH access

## Quick Start

### 1. Configure

Copy and edit the configuration file:

```bash
cp config/homelab.example.yml config/homelab.yml
# Edit config/homelab.yml with your values
```

Generate Ansible inventory, Terraform variables, and patch platform-core Helm values:

```bash
python3 scripts/render-config.py
```

This creates/patches:
- `bootstrap/ansible/inventory/hosts` — Ansible inventory
- `bootstrap/terraform/terraform.tfvars` — Terraform variables
- `platform-core/**/values.yaml` — Replaces `__PLACEHOLDER__` strings with values from your config

### 2. Provision k3s Cluster

See [docs/ansible-k3s-provisioning.md](docs/ansible-k3s-provisioning.md) for detailed Ansible usage.

**Quick version:**

```bash
# Generate SSH key for Ansible
mkdir -p ~/.ssh/homelab
ssh-keygen -t ed25519 -f ~/.ssh/homelab/homelab_ansible -C "ansible@homelab"

# Ensure target has Python
ssh <user>@<server-ip> "sudo apt update && sudo apt install -y python3"

# Create ansible account (from bootstrap/ansible/)
cd bootstrap/ansible
ANSIBLE_PASSWORD='your-secure-password' \
  ansible-playbook -u <bootstrap-user> playbooks/create_account.yml --ask-pass --ask-become-pass

# Install k3s (automatically fetches kubeconfig)
ansible-playbook -u ansible playbooks/install_k3s.yml \
  --private-key ~/.ssh/homelab/homelab_ansible --ask-become-pass

# Verify
kubectl config use-context homelab
kubectl get nodes
```

### 3. Bootstrap Platform

```bash
cd bootstrap/terraform
terraform init
terraform plan
terraform apply
```

This deploys Cilium, Gitea, and ArgoCD via Helm, then runs a bootstrap script that:

1. Creates a `homelab` organisation and `argocd-bot` user in Gitea
2. Creates the `platform-core` repository
3. Pushes all Helm charts from `platform-core/` to Gitea
4. Creates an `argocd-repositories` secret so ArgoCD can pull from Gitea
5. Applies an ApplicationSet that auto-discovers every `Chart.yaml` in the repo

### 4. Verify

```bash
# Check ArgoCD apps are syncing
kubectl get applications -n argocd
```

All applications should reach `Synced` and `Healthy` status.

## Configuration Reference

`config/homelab.yml` structure:

```yaml
cluster:
  server_ip: 10.0.0.10           # Target server IP

network:
  metallb_ip_range: 10.0.0.20-10.0.0.30  # LoadBalancer IP pool

ingress:
  base_domain: lab               # Base domain for services
  prefixes:
    argocd: cd                   # cd.lab
    gitea: git                   # git.lab
    vault: secrets               # secrets.lab
    minio: storage               # storage.lab
    minio_api: s3                # s3.lab
```

`render-config.py` uses these values to:
- Generate `terraform.tfvars` with `base_domain`, `argocd_hostname`, and `gitea_hostname`
- Generate Ansible `inventory/hosts` with `server_ip`
- Replace `__PLACEHOLDER__` strings in `platform-core/**/values.yaml` with computed hostnames and IPs

## Post-Bootstrap Operations

### Configure DNS

Platform services are exposed via ingress using hostnames derived from `config/homelab.yml`. Your local DNS must resolve these hostnames to the MetalLB LoadBalancer IP (the first IP in `network.metallb_ip_range`).

| Hostname | Service |
|----------|---------|
| `cd.lab` | ArgoCD |
| `git.lab` | Gitea |
| `secrets.lab` | Vault |
| `storage.lab` | MinIO Console |
| `s3.lab` | MinIO API |

All entries should point to your LoadBalancer IP (e.g., `10.0.0.20`).

**OPNsense/Unbound**: Configure in **Services > Unbound DNS > Host Overrides**.

**Pi-hole**: Add entries in **Local DNS > DNS Records**.

**Other DNS**: Add A records in your DNS server or `/etc/hosts` for testing.

After adding entries, flush your local DNS cache:

```bash
# macOS
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder

# Linux
sudo systemd-resolve --flush-caches

# Windows
ipconfig /flushdns
```

### Trust the Cluster CA

Export and trust the root CA for browser access:

```bash
./scripts/get-ca-cert.sh
# Follow instructions to add to your system trust store
```

### Making Changes Post-Bootstrap

All platform changes are made through the `platform-core` repository in Gitea:

1. Clone `homelab/platform-core` from Gitea
2. Edit Helm chart values or add new charts
3. Push to Gitea
4. ArgoCD automatically detects and applies changes

### Adding a New Platform App

1. Create a new chart directory in `platform-core/<category>/<app-name>/`
2. Add a `Chart.yaml` and `values.yaml`
3. Push to `homelab/platform-core` in Gitea
4. ArgoCD automatically discovers the new `Chart.yaml` and creates an Application

## Credentials

```bash
# Gitea admin
kubectl get secret -n gitea gitea-admin -o jsonpath='{.data.username}' | base64 -d
kubectl get secret -n gitea gitea-admin -o jsonpath='{.data.password}' | base64 -d

# ArgoCD admin
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# MinIO API + Console
kubectl get secret -n minio minio -o jsonpath='{.data.root-user}' | base64 -d
kubectl get secret -n minio minio -o jsonpath='{.data.root-password}' | base64 -d
```

### Vault Credentials

Vault is configured to auto-initialise and auto-unseal. On first startup, it creates a secret containing the root token and unseal keys:

For full Vault and ESO architecture details, see [docs/secrets-management.md](docs/secrets-management.md).

```bash
kubectl get secret -n vault init-credentials -o jsonpath='{.data}' | jq
```

The secret contains:
- `root-token` — Vault root token for administrative access
- `unseal-key-1`, `unseal-key-2`, `unseal-key-3` — Shamir unseal keys

> **Warning**: Back up this secret immediately. If `init-credentials` is deleted and you cannot recover the root token and unseal keys, you will permanently lose access to all data stored in Vault.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Bootstrap script fails | Check `terraform apply` output for the specific phase and error |
| ArgoCD not syncing | Verify `argocd-repositories` secret exists in `argocd` namespace |
| App not deploying | Confirm `Chart.yaml` exists in `platform-core/<category>/<app>/` |
| Kubeconfig not working | Re-run `ansible-playbook playbooks/fetch_kubeconfig.yml` |
| Port-forward fails | Ensure Gitea pod is running: `kubectl get pods -n gitea` |

## Directory Structure

```
homelab-idp/
├── config/
│   ├── homelab.example.yml       # Configuration template
│   └── homelab.yml               # Your local config (gitignored)
├── scripts/
│   ├── render-config.py          # Generate inventory, tfvars, patch platform-core
│   └── get-ca-cert.sh            # Export cluster CA certificate
├── bootstrap/
│   ├── ansible/                  # k3s provisioning
│   │   ├── ansible.cfg
│   │   ├── inventory/hosts       # Generated by render-config.py
│   │   ├── playbooks/
│   │   └── ansible_collections/
│   └── terraform/                # One-shot platform bootstrap
│       ├── main.tf               # Cilium, Gitea, ArgoCD, Bootstrap modules
│       ├── variables.tf
│       ├── providers.tf
│       └── core/
│           ├── cilium/           # Cilium CNI Helm release
│           ├── gitea/            # Gitea Helm release
│           ├── argocd/           # ArgoCD Helm release
│           └── bootstrap/        # local-exec bootstrap script
│               ├── scripts/
│               │   └── bootstrap.sh
│               └── templates/
│                   └── appset.yaml
└── platform-core/                # Helm charts managed by ArgoCD
    ├── core/
    │   ├── argocd/
    │   ├── cert-manager/
    │   ├── cilium/
    │   ├── gitea/
    │   ├── ingress-nginx/
    │   └── metallb/
    ├── security/
    │   ├── external-secrets/
    │   └── vault/
    ├── storage/
    │   ├── cloudnative-pg/
    │   └── minio/
    └── controlplane/
        ├── crossplane/
        └── crossplane-compositions/
```
