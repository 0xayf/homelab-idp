output "admin_username" {
  description = "The Gitea admin username."
  value       = var.admin_username
}

output "admin_password_secret_name" {
  description = "The name of the Kubernetes secret holding the Gitea admin password."
  value       = kubernetes_secret_v1.gitea_admin.metadata[0].name
}

output "admin_password" {
  description = "The Gitea admin password."
  value       = random_password.admin_password.result
  sensitive   = true
}

output "namespace" {
  description = "The namespace where Gitea is deployed."
  value       = var.namespace
}