locals {
  appset_manifest = templatefile("${path.module}/templates/appset.yaml", {
    namespace               = var.argocd_namespace
    platform_org_name       = var.platform_org_name
    platform_core_repo_name = var.platform_core_repo_name
  })
}

resource "terraform_data" "bootstrap" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/bootstrap.sh"

    environment = {
      KUBECONFIG              = pathexpand(var.kubeconfig_path)
      KUBE_CONTEXT            = var.kubeconfig_context
      GITEA_ADMIN_USER        = var.gitea_admin_user
      GITEA_ADMIN_PASSWORD    = var.gitea_admin_password
      GITEA_NAMESPACE         = var.gitea_namespace
      PLATFORM_ORG_NAME       = var.platform_org_name
      PLATFORM_CORE_REPO_NAME = var.platform_core_repo_name
      PLATFORM_CORE_PATH      = var.platform_core_path
      ARGOCD_NAMESPACE        = var.argocd_namespace
      APPSET_MANIFEST         = local.appset_manifest
    }
  }
}
