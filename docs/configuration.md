# Configuration Reference

This document defines `config/homelab.yaml`, profile templates, and what `render-config.py` generates.

## Profile Templates

- `config/homelab.kind.example.yaml` - local Kind profile
- `config/homelab.k3s.example.yaml` - real k3s profile

Recommended workflow:

```bash
cp config/homelab.kind.example.yaml config/homelab.yaml   # or homelab.k3s.example.yaml
python3 scripts/render-config.py --config config/homelab.yaml
```

## Schema

```yaml
cluster:
  server_ip: 10.0.0.10

storage:
  default_class: local-path

network:
  metallb_ip_range: 10.0.0.20-10.0.0.30
  ingress_nginx_loadbalancer_ip: 10.0.0.20
  gitea_ssh_loadbalancer_ip: 10.0.0.21
  gitea_ssh_allowed_sources:
    - 10.0.0.0/24

ingress:
  base_domain: lab
  prefixes:
    argocd: cd
    gitea: git
    gitea_ssh: git-ssh
    vault: secrets
    minio: storage
    minio_api: s3
```

## Field Reference

| Field | Required | Default | Notes |
|---|---|---|---|
| `cluster.server_ip` | yes | none | Target server IP for generated Ansible inventory. For Kind, use `127.0.0.1`. |
| `storage.default_class` | no | `local-path` | StorageClass rendered into stateful charts (currently Vault and MinIO). Use `standard` for Kind in most setups. |
| `network.metallb_ip_range` | yes | none | MetalLB address pool range. Must be routable on your cluster network. |
| `network.ingress_nginx_loadbalancer_ip` | yes | none | Fixed VIP for ingress-nginx service (HTTP/HTTPS). |
| `network.gitea_ssh_loadbalancer_ip` | yes | none | Fixed VIP for Gitea SSH service. |
| `network.gitea_ssh_allowed_sources` | no | `[]` | Optional CIDR allowlist for Gitea SSH LoadBalancer service. Delete this block for unrestricted source ranges. |
| `ingress.base_domain` | yes | none | Base domain used to construct hostnames. |
| `ingress.prefixes.argocd` | yes | none | ArgoCD host prefix. |
| `ingress.prefixes.gitea` | yes | none | Gitea UI/API host prefix. |
| `ingress.prefixes.gitea_ssh` | yes | none | Gitea SSH clone host prefix. |
| `ingress.prefixes.vault` | yes | none | Vault host prefix. |
| `ingress.prefixes.minio` | yes | none | MinIO console host prefix. |
| `ingress.prefixes.minio_api` | yes | none | MinIO API host prefix. |

## Environment Guidance

### Kind

- `storage.default_class: standard`
- MetalLB range and VIPs must be inside Kind network subnet
- `cluster.server_ip: 127.0.0.1` is sufficient

### k3s

- `storage.default_class: local-path`
- MetalLB range and VIPs should be in your homelab LAN subnet
- `cluster.server_ip` should be the k3s server host IP

## Rendered Outputs

`scripts/render-config.py` generates/patches:

- `bootstrap/ansible/inventory/hosts`
- `bootstrap/terraform/terraform.tfvars`
- `platform-core/**/values.yaml` placeholder replacements

Important:

- This repository is intended to stay **non-rendered** in git.
- Rendered values are local workspace state used during bootstrap.
- Day-2 changes happen in Gitea `homelab/platform-core` after bootstrap handoff.
