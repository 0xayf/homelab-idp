resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  create_namespace = true
  namespace        = var.namespace

  values = [
    templatefile("${path.module}/values.yaml", {
      hostname = var.hostname
    })
  ]
}