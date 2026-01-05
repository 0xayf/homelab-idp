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

module "argocd_appset" {
  source = "./core/argocd-appset"

  argocd_namespace        = module.argocd.namespace
  platform_org_name       = var.platform_org_name
  platform_apps_repo_name = var.platform_apps_repo_name
  kubeconfig_path         = var.kubeconfig_path
  kubeconfig_context      = var.kubeconfig_context

  depends_on = [module.argocd]
}
