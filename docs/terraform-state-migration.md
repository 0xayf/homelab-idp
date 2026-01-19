# Terraform State Migration to MinIO

## Overview

After running `terraform apply` to bootstrap the platform, your Terraform state exists as a local file at `bootstrap/terraform/terraform.tfstate`. This presents several challenges:

- **No collaboration**: State is tied to your local machine
- **No state locking**: Risk of concurrent modifications
- **No versioning**: Difficult to recover from mistakes
- **Not GitOps-friendly**: State shouldn't be committed to version control

This guide walks through migrating Terraform state to MinIO (S3-compatible object storage) running in your cluster, enabling remote state management for `platform-core`.

### What Gets Migrated

The bootstrap process creates resources in two categories:

**Post-bootstrap resources** (migrated to MinIO):
- `module.cilium` - CNI networking
- `module.gitea` - Git server
- `module.argocd` - Continuous deployment
- `module.argocd_appset` - ApplicationSet for platform-apps

**Bootstrap-only resources** (excluded from migration):
- `module.gitops_bootstrap` - One-time job that creates Gitea repos, pushes configs, and wires ArgoCD

The bootstrap resources are excluded because they only run once during initial setup and are not needed for ongoing platform management.

## Prerequisites

- Completed platform bootstrap (`terraform apply` from `bootstrap/terraform/`)
- MinIO deployed with API and console ingresses:
  - `s3.lab` - S3 API endpoint
  - `storage.lab` - Console UI
- DNS configured for both hostnames pointing to your ingress IP
- `jq` installed for JSON processing

## Migration Steps

### 1. Configure DNS

Add DNS overrides pointing to your ingress LoadBalancer IP (e.g., `10.0.0.20`):

| Hostname | IP |
|----------|-----|
| `s3.lab` | `10.0.0.20` |
| `storage.lab` | `10.0.0.20` |

After adding DNS entries, flush your local DNS cache:

```bash
# macOS
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

Verify resolution:

```bash
nslookup s3.lab
```

### 2. Get MinIO Credentials

Export the MinIO root credentials as AWS environment variables:

```bash
export AWS_ACCESS_KEY_ID=$(kubectl get secret -n minio minio -o jsonpath='{.data.root-user}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(kubectl get secret -n minio minio -o jsonpath='{.data.root-password}' | base64 -d)
```

### 3. Clone platform-core from Gitea

Clone the `platform-core` repository from Gitea. It already includes `backend.tf` with the S3 backend configuration for MinIO.

> **Tip**: This is a good time to create your own Gitea account and SSH key for ongoing development. For this migration, you can use the admin credentials:

```bash
export GITEA_USER=$(kubectl get secret -n gitea gitea-admin-credentials -o jsonpath='{.data.username}' | base64 -d)
export GITEA_PASS=$(kubectl get secret -n gitea gitea-admin-credentials -o jsonpath='{.data.password}' | base64 -d | jq -sRr @uri)

git clone "https://${GITEA_USER}:${GITEA_PASS}@git.lab/homelab/platform-core.git"
cd platform-core
```

> **Note**: The `backend.tf` was automatically configured during bootstrap with the correct MinIO API hostname. The `region` value is required by Terraform but ignored by MinIO. The `skip_*` options disable AWS-specific validations that don't apply to MinIO.

### 4. Extract and Filter State

Pull the current state from the bootstrap directory (in your homelab-idp repo) and remove bootstrap-only resources:

```bash
cd /path/to/homelab-idp/bootstrap/terraform

# Extract current state
terraform state pull > /tmp/full-state.json

# Remove gitops_bootstrap resources
jq 'del(.resources[] | select(.module == "module.gitops_bootstrap"))' \
  /tmp/full-state.json > /tmp/filtered-state.json

# Verify the filtered state contains only the expected modules
jq -r '.resources[].module // "root"' /tmp/filtered-state.json | sort -u
```

Expected output:
```
module.argocd
module.argocd_appset
module.cilium
module.gitea
```

### 5. Initialize and Push State

Return to the `platform-core` repository and migrate the state:

```bash
cd /path/to/platform-core

# Initialize with the new S3 backend
terraform init

# Push the filtered state to MinIO
terraform state push /tmp/filtered-state.json

# Verify the state was pushed correctly
terraform state list
```

Expected output:
```
module.argocd.helm_release.argocd
module.argocd.kubernetes_manifest.argocd_ingress
module.argocd_appset.kubectl_manifest.appset
module.argocd_appset.null_resource.wait_for_argocd_repo_secret
module.cilium.helm_release.cilium
module.gitea.helm_release.gitea
module.gitea.kubernetes_manifest.gitea_ingress
module.gitea.kubernetes_secret_v1.gitea_admin_credentials
module.gitea.random_password.admin_password
```

### 6. Validate

Run a plan to confirm the state matches your infrastructure:

```bash
terraform plan
```

Expected output:
```
No changes. Your infrastructure matches the configuration.
```

### 7. Verify in MinIO Console

Open `https://storage.lab` in your browser and log in with the MinIO credentials. Navigate to the `terraform-state` bucket and confirm the state file exists at `platform-core/terraform.tfstate`.

## Troubleshooting

### DNS Resolution Fails

If `terraform init` fails with "no such host":

1. Verify DNS resolution works: `nslookup s3.lab`
2. Flush DNS cache (see Step 1)
3. Check that your DNS server has the override configured

macOS applications sometimes cache DNS independently. If `nslookup` works but `terraform` fails, flushing the cache usually resolves this.

### Access Denied

If you receive S3 access denied errors:

1. Verify environment variables are set: `echo $AWS_ACCESS_KEY_ID`
2. Confirm the `terraform-state` bucket exists in MinIO
3. Check MinIO credentials are correct

### State Push Fails

If `terraform state push` fails:

1. Ensure the backend was initialized: `terraform init`
2. Verify the filtered state file is valid JSON: `jq . /tmp/filtered-state.json`
3. Check MinIO is accessible: `curl -I https://s3.lab`

## Post-Migration

After successful migration:

1. Commit `backend.tf` and `.gitignore` to your `platform-core` repository
2. Push to Gitea
3. Future `terraform` operations will automatically use the remote state in MinIO

The local state file in `bootstrap/terraform/` can be deleted - it is no longer used.
