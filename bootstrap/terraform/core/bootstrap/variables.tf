variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
}

variable "kubeconfig_context" {
  description = "The Kubernetes context to use from the kubeconfig file."
  type        = string
}

variable "gitea_admin_user" {
  description = "The admin username for the Gitea instance."
  type        = string
}

variable "gitea_admin_password" {
  description = "The admin password for the Gitea instance."
  type        = string
  sensitive   = true
}

variable "gitea_namespace" {
  description = "The namespace where Gitea is deployed."
  type        = string
}

variable "platform_core_repo_name" {
  description = "The name of the Gitea repository for platform-core (ArgoCD-managed)."
  type        = string
  default     = "platform-core"
}

variable "platform_core_path" {
  description = "Absolute path to the platform-core folder."
  type        = string
}

variable "platform_org_name" {
  description = "The name of the Gitea organization for the platform."
  type        = string
}

variable "argocd_namespace" {
  description = "The namespace where ArgoCD is deployed."
  type        = string
}

