resource "kubernetes_config_map_v1" "bootstrap_scripts" {
  metadata {
    name      = "gitops-bootstrap-scripts"
    namespace = var.gitea_namespace
  }
  data = {
    for f in fileset("${path.module}/scripts", "*.sh") :
    f => file("${path.module}/scripts/${f}")
  }
}
