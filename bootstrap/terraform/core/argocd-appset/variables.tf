variable "argocd_namespace" {
  description = "The namespace where ArgoCD is deployed."
  type        = string
}

variable "platform_org_name" {
  description = "The name of the Gitea organization for the platform."
  type        = string
}

variable "platform_apps_repo_name" {
  description = "The name of the Gitea repository for platform apps (ArgoCD-managed)."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
}

variable "kubeconfig_context" {
  description = "The Kubernetes context to use from the kubeconfig file."
  type        = string
}
