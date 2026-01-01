resource "kubernetes_job_v1" "gitops_bootstrap" {
  metadata {
    generate_name = "gitops-bootstrap-"
    namespace     = var.gitea_namespace
  }

  wait_for_completion = true

  spec {
    ttl_seconds_after_finished = 300

    template {
      metadata {
        generate_name = "gitops-bootstrap-"
      }
      spec {
        service_account_name = kubernetes_service_account_v1.bootstrap_sa.metadata[0].name
        restart_policy       = "OnFailure"

        container {
          name    = "bootstrap"
          image   = "alpine/k8s:1.30.14"
          command = ["/bin/sh", "-c", "/scripts/1-create-org-user.sh && /scripts/2-create-repo.sh && /scripts/3-push-config.sh && /scripts/4-setup-argocd.sh"]

          env {
            name  = "GITEA_ADMIN_USER"
            value = var.gitea_admin_user
          }
          env {
            name = "GITEA_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = var.gitea_admin_secret_name
                key  = "password"
              }
            }
          }
          env {
            name  = "PLATFORM_REPO_NAME"
            value = var.platform_repo_name
          }
          env {
            name  = "PLATFORM_ORG_NAME"
            value = var.platform_org_name
          }
          env {
            name  = "ARGO_NAMESPACE"
            value = var.argocd_namespace
          }
          env {
            name  = "VAULT_HOSTNAME"
            value = var.vault_hostname
          }
          env {
            name  = "METALLB_IP_RANGE"
            value = var.metallb_ip_range
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }
        }
        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map_v1.bootstrap_scripts.metadata[0].name
            default_mode = "0755"
          }
        }
      }
    }
  }
}