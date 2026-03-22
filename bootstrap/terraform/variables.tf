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

variable "platform_org_name" {
  description = "The name of the Gitea organisation for the platform repos."
  type        = string
  default     = "homelab"
}

variable "platform_core_repo_name" {
  description = "The name of the Gitea repository for platform core (ArgoCD-managed)."
  type        = string
  default     = "platform-core"
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

variable "gitea_ssh_hostname" {
  description = "The fully qualified domain name for the Gitea SSH endpoint."
  type        = string
}

variable "gitea_ssh_loadbalancer_ip" {
  description = "The dedicated LoadBalancer IP for the Gitea SSH service."
  type        = string
}

variable "gitea_ssh_allowed_sources" {
  description = "Optional source CIDR allowlist for the Gitea SSH LoadBalancer service."
  type        = list(string)
  default     = []
}

variable "keycloak_hostname" {
  description = "The fully qualified domain name for Keycloak."
  type        = string
}

variable "traefik_hostname" {
  description = "The fully qualified domain name for the Traefik dashboard."
  type        = string
}
