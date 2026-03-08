resource "helm_release" "gitea" {
  name             = "gitea"
  repository       = "https://dl.gitea.com/charts/"
  chart            = "gitea"
  version          = var.gitea_chart_version
  create_namespace = true
  namespace        = var.namespace

  values = [
    templatefile("${path.module}/values.yaml", {
      hostname            = var.hostname,
      ssh_hostname        = var.ssh_hostname,
      ssh_loadbalancer_ip = var.ssh_loadbalancer_ip,
      ssh_allowed_sources = var.ssh_allowed_sources,
      username            = var.admin_username,
      password            = random_password.admin_password.result,
      email               = var.admin_email
    })
  ]
}
