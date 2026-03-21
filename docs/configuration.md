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
  metallb_ip_range: 10.0.0.20-10.0.0.21
  traefik_loadbalancer_ip: 10.0.0.20
  gitea_ssh_loadbalancer_ip: 10.0.0.21
  gitea_ssh_allowed_sources:
    - 10.0.0.0/24
  traefik_dashboard_allowed_sources:
    - 10.0.0.0/24

admin:
  first_name: Lab
  last_name: Admin
  email: admin@local.lab

dns:
  base_domain: local.lab
  prefixes:
    argocd: cd
    gitea: git
    gitea_ssh: git-ssh
    keycloak: auth
    traefik: gateway
    vault: secrets
    rustfs_console: storage
    rustfs_api: s3
```

## Field Reference

| Field | Required | Default | Notes |
|---|---|---|---|
| `cluster.server_ip` | yes | none | Target server IP for generated Ansible inventory. For Kind, use `127.0.0.1`. |
| `storage.default_class` | no | `local-path` | StorageClass rendered into stateful charts (Vault, RustFS). Use `standard` for Kind. |
| `network.metallb_ip_range` | yes | none | MetalLB address pool range. Must be routable on your cluster network. |
| `network.traefik_loadbalancer_ip` | yes | none | Fixed VIP for Traefik Gateway API service (HTTP/HTTPS). |
| `network.gitea_ssh_loadbalancer_ip` | yes | none | Fixed VIP for Gitea SSH service. |
| `network.gitea_ssh_allowed_sources` | no | `[]` | Optional CIDR allowlist for Gitea SSH LoadBalancer. Delete block to allow all. |
| `network.traefik_dashboard_allowed_sources` | no | `[]` | Optional CIDR allowlist for Traefik dashboard. Delete block to allow all. |
| `admin.first_name` | no | `Lab` | Keycloak lab-admin user first name. |
| `admin.last_name` | no | `Admin` | Keycloak lab-admin user last name. |
| `admin.email` | no | `admin@local.lab` | Keycloak lab-admin user email. |
| `dns.base_domain` | yes | none | Base domain for hostnames. Prefixes are prepended: `{prefix}.{base_domain}`. |
| `dns.prefixes.argocd` | yes | none | ArgoCD host prefix. |
| `dns.prefixes.gitea` | yes | none | Gitea UI/API host prefix. |
| `dns.prefixes.gitea_ssh` | yes | none | Gitea SSH clone host prefix. |
| `dns.prefixes.keycloak` | yes | none | Keycloak OIDC host prefix. |
| `dns.prefixes.traefik` | yes | none | Traefik dashboard host prefix. |
| `dns.prefixes.vault` | yes | none | Vault host prefix. |
| `dns.prefixes.rustfs_console` | yes | none | RustFS console host prefix. |
| `dns.prefixes.rustfs_api` | yes | none | RustFS S3 API host prefix. |

## Environment Guidance

### Kind

- `storage.default_class: standard`
- MetalLB range and VIPs must be inside Kind network subnet
- `cluster.server_ip: 127.0.0.1` is sufficient
- Run `docs/examples/kind-patch-dns.sh` after bootstrap to resolve `*.local.lab` inside the cluster

### k3s

- `storage.default_class: local-path`
- MetalLB range and VIPs should be in your homelab LAN subnet
- `cluster.server_ip` should be the k3s server host IP
- Configure DNS (e.g., OPNsense Unbound) to point `*.local.lab` to the Traefik LB IP

## Rendered Outputs

`scripts/render-config.py` generates/patches:

- `bootstrap/ansible/inventory/hosts`
- `bootstrap/terraform/terraform.tfvars`
- `platform-core/**/values.yaml` placeholder replacements

Important:

- This repository is intended to stay **non-rendered** in git.
- Rendered values are local workspace state used during bootstrap.
- Day-2 changes happen in Gitea `homelab/platform-core` after bootstrap handoff.
