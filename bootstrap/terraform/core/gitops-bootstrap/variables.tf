variable "gitea_admin_user" {
  description = "The admin username for the Gitea instance."
  type        = string
}

variable "gitea_admin_secret_name" {
  description = "The name of the Kubernetes secret holding the Gitea admin credentials."
  type        = string
}

variable "gitea_namespace" {
  description = "The namespace where Gitea is deployed."
  type        = string
}

variable "platform_repo_name" {
  description = "The name of the platform repository to create in Gitea."
  type        = string
}

variable "platform_org_name" {
  description = "The name of the Gitea organization to create for the platform."
  type        = string
}

variable "argocd_namespace" {
  description = "The namespace where ArgoCD is deployed."
  type        = string
}

variable "vault_hostname" {
  description = "The fully qualified domain name for Vault."
  type        = string
}

variable "metallb_ip_range" {
  description = "MetalLB IP address pool range."
  type        = string
}
