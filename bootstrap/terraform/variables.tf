

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "The Kubernetes context to use from the kubeconfig file"
  type        = string
  default     = "homelab"
}

variable "base_domain" {
  description = "The base domain for the platform."
  type        = string
}

variable "argocd_hostname" {
  description = "The fully qualified domain name for ArgoCD."
  type        = string
}

variable "gitea_hostname" {
  description = "The fully qualified domain name for Gitea."
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

variable "platform_org_name" {
  description = "The name of the Gitea organisation for the platform repo."
  type        = string
  default     = "homelab"
}
variable "platform_repo_name" {
  description = "The name of the Gitea repository for the platform config."
  type        = string
  default     = "platform"
}