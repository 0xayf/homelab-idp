# Install on k3s (Recommended)

This is the recommended path for real homelab usage.

## Prerequisites

- Ubuntu host reachable over SSH
- Local machine with `python3`, `ansible`, `terraform`, `kubectl`, `jq`, `curl`, `git`, `sed`
- SSH access to the host with sudo
- DNS control for your lab domain (for example OPNsense Unbound overrides)

## 1) Create your config

From repo root:

```bash
cp config/homelab.k3s.example.yaml config/homelab.yaml
```

Edit `config/homelab.yaml` for your environment:

- `cluster.server_ip`
- MetalLB range/VIPs (`network.*`)
- ingress domain/prefixes (`ingress.*`)
- optional `network.gitea_ssh_allowed_sources`

For k3s defaults, keep:

- `storage.default_class: local-path`

## 2) Render generated bootstrap files

```bash
python3 scripts/render-config.py --config config/homelab.yaml
```

This generates:

- `bootstrap/ansible/inventory/hosts`
- `bootstrap/terraform/terraform.tfvars`
- rendered `platform-core/**/values.yaml` in your local workspace

## 3) Provision k3s with Ansible

Detailed runbook: `docs/ansible-k3s-provisioning.md`

Typical flow:

```bash
cd bootstrap/ansible

# Create ansible account on target
ANSIBLE_PASSWORD='your-secure-password' ansible-playbook -u <bootstrap-user> playbooks/create_account.yml --ask-pass --ask-become-pass

# Install k3s and fetch kubeconfig
ansible-playbook -u ansible playbooks/install_k3s.yml --private-key ~/.ssh/homelab/homelab_ansible --ask-become-pass
```

Validate context:

```bash
kubectl config use-context homelab
kubectl get nodes
```

## 4) Run Terraform bootstrap

```bash
cd bootstrap/terraform
terraform init
terraform apply -var kubeconfig_context=homelab -var kubeconfig_path=~/.kube/config
```

Terraform deploys Cilium, Gitea, ArgoCD, then runs bootstrap script to hand ownership to ArgoCD.

Deep dive: `docs/terraform-bootstrap-handoff.md`

## 5) Configure DNS and TLS trust

Map hostnames to ingress and SSH VIPs from `config/homelab.yaml`:

- ingress hosts -> `network.ingress_nginx_loadbalancer_ip`
- `git-ssh.<base-domain>` -> `network.gitea_ssh_loadbalancer_ip`

Export and trust cluster CA locally:

```bash
./scripts/get-ca-cert.sh
```

## 6) Verify

```bash
kubectl get applications -n argocd
kubectl -n gitea get svc gitea-ssh -o wide
```

Expected steady state: all apps `Synced` + `Healthy`.

## Day-2 Changes

After bootstrap, treat Gitea `homelab/platform-core` as source of truth:

1. Clone `homelab/platform-core`
2. Change chart values or add charts
3. Push
4. ArgoCD reconciles automatically
