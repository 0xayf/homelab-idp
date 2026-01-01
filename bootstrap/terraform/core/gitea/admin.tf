resource "random_password" "admin_password" {
  length           = 21
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "kubernetes_secret_v1" "gitea_admin_credentials" {
  metadata {
    name      = "gitea-admin-credentials"
    namespace = var.namespace
  }
  data = {
    username = var.admin_username
    password = random_password.admin_password.result
  }
  type = "Opaque"

  depends_on = [helm_release.gitea]
}
