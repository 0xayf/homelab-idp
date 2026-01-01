resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_chart_version
  namespace  = "kube-system"

  values = [
    file("${path.module}/values.yaml")
  ]
}