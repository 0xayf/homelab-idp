resource "random_password" "admin_password" {
  length           = 21
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "kubernetes_secret_v1" "gitea_admin" {
  metadata {
    name      = "gitea-admin"
    namespace = var.namespace
  }
  data = {
    username = var.admin_username
    password = random_password.admin_password.result
  }
  type = "Opaque"

  depends_on = [helm_release.gitea]
}
