# Bootstrap Module

The bootstrap module (`bootstrap/terraform/core/bootstrap/`) is the final step of `terraform apply`. It runs a shell script via `local-exec` that connects Gitea and ArgoCD, then hands ownership of the entire platform to ArgoCD.

## How It Works

Terraform deploys three Helm releases — Cilium, Gitea, and ArgoCD — then invokes `bootstrap.sh` as a `terraform_data` resource with a `local-exec` provisioner. The script runs on your local machine (not in the cluster) and communicates with Gitea via `kubectl port-forward`.

### Phases

The bootstrap script executes five phases sequentially:

**Phase 1 — Gitea organisation and bot user**

Creates a `homelab` organisation and an `argocd-bot` user in Gitea. The bot user is added to the organisation's Owners team. If these already exist (idempotent re-run), the phase is skipped.

**Phase 2 — Repository creation**

Creates the `platform-core` repository under the `homelab` organisation. This is the single repository that ArgoCD watches.

**Phase 3 — Push Helm charts**

Copies the local `platform-core/` directory (which `render-config.py` has already patched with your hostnames and IPs), initialises a git repo, and force-pushes to Gitea. The `.git/` directory from the source is stripped — Gitea gets a clean initial commit.

**Phase 4 — ArgoCD repository secret**

Creates (or rotates) a Gitea access token for the `argocd-bot` user, then applies an `argocd-repositories` Secret in the `argocd` namespace. This secret tells ArgoCD how to authenticate with Gitea using the cluster-internal URL (`http://gitea-http.gitea.svc.cluster.local:3000`).

**Phase 5 — ApplicationSet**

Applies an ApplicationSet that uses a git file generator to discover every `Chart.yaml` in the `platform-core` repository. Each chart automatically becomes an ArgoCD Application with:

- Automated sync (prune + self-heal)
- `CreateNamespace=true`
- Namespace matching the chart directory name
- Release name matching the chart directory name

## ArgoCD Takeover

Once the ApplicationSet is applied, ArgoCD begins deploying every Helm chart in `platform-core`. This includes charts for Cilium, Gitea, and ArgoCD itself — the same services Terraform just deployed.

ArgoCD's sync policy (`selfHeal: true`) means it will reconcile any drift. Since the Helm chart values in `platform-core` match what Terraform deployed, the initial sync should show no changes. From this point forward, ArgoCD owns all resources.

### What happens to Terraform's Helm releases?

Terraform created Helm releases for Cilium, Gitea, and ArgoCD during bootstrap. ArgoCD then deploys the same applications from `platform-core`. ArgoCD adopts the existing resources because the release names and namespaces match. Terraform's state becomes irrelevant — it is never applied again.

## Port-Forwarding

During bootstrap, Gitea has no ingress (ingress-nginx hasn't been deployed yet). The script uses `kubectl port-forward` to expose Gitea's HTTP service on `localhost:3000`, allowing the Gitea API calls and git push to work from your local machine.

The port-forward is cleaned up automatically when the script exits (via `trap`).

## Configuration Flow

```
config/homelab.yml
        │
        v
render-config.py ──> bootstrap/terraform/terraform.tfvars (base_domain, argocd_hostname, gitea_hostname)
        │        ──> bootstrap/ansible/inventory/hosts (server_ip)
        │        ──> platform-core/**/values.yaml (replaces __PLACEHOLDER__ strings)
        │
        v
terraform apply
        │
        ├─ module.cilium    (Helm)
        ├─ module.gitea     (Helm)
        ├─ module.argocd    (Helm)
        └─ module.bootstrap (local-exec)
                │
                └─ bootstrap.sh
                     ├─ Phase 1: Gitea org + bot user
                     ├─ Phase 2: Create repo
                     ├─ Phase 3: Push platform-core
                     ├─ Phase 4: ArgoCD repo secret
                     └─ Phase 5: Apply ApplicationSet
                                    │
                                    v
                        ArgoCD manages everything
```

## Re-running Bootstrap

The bootstrap module uses `terraform_data` which runs on every `terraform apply`. However, the script is idempotent:

- Gitea org/user/repo creation checks for existence before creating
- Git push uses `--force` to overwrite
- The ArgoCD token is rotated and the secret is re-applied
- The ApplicationSet is applied with `kubectl apply` (update-or-create)

In practice, you should never need to re-run `terraform apply` after the initial bootstrap. All changes go through `platform-core` in Gitea.

## Terraform Module Interface

The bootstrap module accepts these variables:

| Variable | Description |
|----------|-------------|
| `kubeconfig_path` | Path to kubeconfig file |
| `kubeconfig_context` | Kubernetes context name |
| `gitea_admin_user` | Gitea admin username (from gitea module) |
| `gitea_admin_password` | Gitea admin password (from gitea module, sensitive) |
| `gitea_namespace` | Namespace where Gitea is deployed |
| `platform_org_name` | Gitea organisation name (default: `homelab`) |
| `platform_core_repo_name` | Repository name (default: `platform-core`) |
| `platform_core_path` | Local path to the platform-core directory |
| `argocd_namespace` | Namespace where ArgoCD is deployed |

The module has no outputs — it is a one-shot side-effect.
