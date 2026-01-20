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

module "bootstrap" {
  source = "./core/bootstrap"

  kubeconfig_path         = var.kubeconfig_path
  kubeconfig_context      = var.kubeconfig_context
  gitea_admin_user        = module.gitea.admin_username
  gitea_admin_password    = module.gitea.admin_password
  gitea_namespace         = module.gitea.namespace
  platform_org_name       = var.platform_org_name
  platform_core_repo_name = var.platform_core_repo_name
  platform_core_path      = abspath("${path.module}/../../platform-core")
  argocd_namespace        = module.argocd.namespace

  depends_on = [
    module.gitea,
    module.argocd
  ]
}