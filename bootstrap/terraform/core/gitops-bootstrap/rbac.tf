resource "kubernetes_service_account_v1" "bootstrap_sa" {
  metadata {
    name      = "gitops-bootstrap-sa"
    namespace = var.gitea_namespace
  }
}

resource "kubernetes_role_v1" "argocd_permissions" {
  metadata {
    name      = "gitops-bootstrap-argocd-role"
    namespace = var.argocd_namespace
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "get", "patch", "update", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "argocd_permissions" {
  metadata {
    name      = "gitops-bootstrap-argocd-binding"
    namespace = var.argocd_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.argocd_permissions.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.bootstrap_sa.metadata[0].name
    namespace = var.gitea_namespace
  }
}
