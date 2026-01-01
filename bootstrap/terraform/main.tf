module "cilium" {
  source = "./core/cilium"
}

module "gitea" {
  source = "./core/gitea"

  hostname       = var.gitea_hostname
  admin_username = "admin"
  admin_email    = "admin@${var.base_domain}"

  depends_on = [module.cilium]
}

module "argocd" {
  source = "./core/argocd"

  hostname = var.argocd_hostname

  depends_on = [module.cilium]
}

module "gitops_bootstrap" {
  source = "./core/gitops-bootstrap"

  gitea_admin_user        = module.gitea.admin_username
  gitea_admin_secret_name = module.gitea.admin_password_secret_name
  gitea_namespace         = module.gitea.namespace
  platform_org_name       = var.platform_org_name
  platform_repo_name      = var.platform_repo_name
  argocd_namespace        = module.argocd.namespace
  vault_hostname          = var.vault_hostname
  metallb_ip_range        = var.metallb_ip_range

  depends_on = [
    module.gitea,
    module.argocd
  ]
}
