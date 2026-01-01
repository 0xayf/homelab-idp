resource "helm_release" "gitea" {
  name             = "gitea"
  repository       = "https://dl.gitea.com/charts/"
  chart            = "gitea"
  version          = var.gitea_chart_version
  create_namespace = true
  namespace        = var.namespace

  values = [
    templatefile("${path.module}/values.yaml", {
      hostname = var.hostname,
      username = var.admin_username,
      password = random_password.admin_password.result,
      email    = var.admin_email
    })
  ]
}