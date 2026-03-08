# Troubleshooting

## Quick Diagnostics

```bash
kubectl get applications -n argocd
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
```

## Terraform Targeted Wrong Cluster

Symptom:

- Terraform tries to create releases that already exist in your real cluster

Fix:

```bash
terraform apply -var kubeconfig_context=kind-homelab -var kubeconfig_path=~/.kube/config
```

Always pass `kubeconfig_context` explicitly.

## Bootstrap Script Fails Waiting for Gitea API

Symptoms:

- `Timed out waiting for Gitea API via port-forward`
- `kubectl port-forward exited before Gitea API became available`

Checks:

```bash
kubectl -n gitea get pods
kubectl -n gitea get svc gitea-http
kubectl -n gitea get endpoints gitea-http
```

Notes:

- Gitea may still be starting (`Init:*`, image pulls, DB init)
- re-running `terraform apply` after Gitea becomes ready is safe (bootstrap is idempotent)

## Gitea Sync Fails: ingress-nginx Webhook x509 Unknown Authority

Symptom:

- `failed calling webhook "validate.nginx.ingress.kubernetes.io" ... certificate signed by unknown authority`

Cause:

- ingress-nginx admission webhook CA bundle missing or stale during sync

Checks:

```bash
kubectl get validatingwebhookconfiguration ingress-nginx-admission -o yaml
kubectl -n ingress-nginx get jobs,pods,secrets
kubectl get application ingress-nginx -n argocd -o yaml
```

Typical recovery:

- sync/re-sync `ingress-nginx` and `cert-manager`
- then re-sync the failing app (for example `gitea`)

## Vault/MinIO PVC Pending: StorageClass Not Found

Symptom:

- `storageclass.storage.k8s.io "local-path" not found`

Cause:

- Kind often uses `standard`; k3s usually uses `local-path`

Fix:

- set `storage.default_class` correctly in `config/homelab.yaml`
- rerun `scripts/render-config.py`
- re-run bootstrap/sync

Check available classes:

```bash
kubectl get storageclass
```

## Gitea SSH Service Has Pending External IP

Symptom:

- `kubectl -n gitea get svc gitea-ssh` shows `EXTERNAL-IP <pending>`

Cause:

- MetalLB not healthy or IP not in pool

Checks:

```bash
kubectl get application metallb -n argocd
kubectl -n metallb get pods
kubectl -n gitea get svc gitea-ssh -o wide
```

Verify rendered values:

- `network.metallb_ip_range`
- `network.gitea_ssh_loadbalancer_ip`

## Argo Applications Stuck OutOfSync/Progressing

Checks:

```bash
kubectl get application <app> -n argocd -o yaml
kubectl get events -n <app-namespace> --sort-by=.lastTimestamp
```

Common pattern:

- one dependency app is unhealthy (storage, certs, ingress webhook)
- downstream apps recover automatically once dependency is healthy
