module "gitops_bootstrap" {
  source = "./core/gitops-bootstrap"

  gitea_admin_user        = module.gitea.admin_username
  gitea_admin_secret_name = module.gitea.admin_password_secret_name
  gitea_namespace         = module.gitea.namespace
  platform_org_name       = var.platform_org_name
  platform_apps_repo_name = var.platform_apps_repo_name
  platform_core_repo_name = var.platform_core_repo_name
  argocd_namespace        = module.argocd.namespace
  vault_hostname          = var.vault_hostname
  metallb_ip_range        = var.metallb_ip_range
  platform_core_path      = abspath("${path.module}")
  platform_apps_path      = abspath("${path.module}/../../platform-apps")

  depends_on = [
    module.gitea,
    module.argocd
  ]
}
