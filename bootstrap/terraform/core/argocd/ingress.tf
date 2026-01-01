resource "kubernetes_manifest" "argocd_ingress" {
  manifest = yamldecode(templatefile("${path.module}/templates/ingress.yaml", {
    namespace = var.namespace,
    hostname  = var.hostname
  }))

  depends_on = [ helm_release.argocd ]
}