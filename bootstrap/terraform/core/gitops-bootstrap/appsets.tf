resource "kubectl_manifest" "appset" {
  yaml_body = templatefile("${path.module}/templates/appset.yaml", {
    namespace          = var.argocd_namespace,
    platform_org_name  = var.platform_org_name,
    platform_repo_name = var.platform_repo_name
  })

  depends_on = [ kubernetes_job_v1.gitops_bootstrap ]
}