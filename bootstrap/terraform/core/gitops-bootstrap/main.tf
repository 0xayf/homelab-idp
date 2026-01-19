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
          command = ["/bin/sh", "-c", "/scripts/1-create-org-argocd-bot.sh && /scripts/2-create-repos.sh && /scripts/3-push-repos.sh && /scripts/4-argocd-repositories-secret.sh"]

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
            name  = "PLATFORM_APPS_REPO_NAME"
            value = var.platform_apps_repo_name
          }
          env {
            name  = "PLATFORM_CORE_REPO_NAME"
            value = var.platform_core_repo_name
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
          env {
            name  = "MINIO_HOSTNAME"
            value = var.minio_hostname
          }
          env {
            name  = "MINIO_API_HOSTNAME"
            value = var.minio_api_hostname
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }

          volume_mount {
            name       = "archives"
            mount_path = "/archives"
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
        volume {
          name = "archives"
          projected {
            sources {
              config_map {
                name = kubernetes_config_map_v1.platform_apps_archive.metadata[0].name
              }
            }
            sources {
              config_map {
                name = kubernetes_config_map_v1.platform_core_archive.metadata[0].name
              }
            }
          }
        }
      }
    }
  }

}
