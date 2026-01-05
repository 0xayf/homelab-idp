resource "null_resource" "wait_for_argocd_repo_secret" {
  triggers = {
    kubeconfig_path    = var.kubeconfig_path
    kubeconfig_context = var.kubeconfig_context
    namespace          = var.argocd_namespace
    secret_name        = "argocd-repositories"
  }

  provisioner "local-exec" {
    command = <<-EOF
      set -e
      export KUBECONFIG="${pathexpand(var.kubeconfig_path)}"
      i=0
      until kubectl --context ${var.kubeconfig_context} -n ${var.argocd_namespace} get secret argocd-repositories >/dev/null 2>&1; do
        i=$((i+1))
        if [ "$i" -ge 60 ]; then
          echo "Timed out waiting for argocd-repositories secret in namespace ${var.argocd_namespace}"
          exit 1
        fi
        echo "Waiting for argocd-repositories secret..."
        sleep 5
      done
    EOF
  }
}

resource "kubectl_manifest" "appset" {
  yaml_body = templatefile("${path.module}/templates/appset.yaml", {
    namespace               = var.argocd_namespace
    platform_org_name       = var.platform_org_name
    platform_apps_repo_name = var.platform_apps_repo_name
  })

  depends_on = [null_resource.wait_for_argocd_repo_secret]
}
