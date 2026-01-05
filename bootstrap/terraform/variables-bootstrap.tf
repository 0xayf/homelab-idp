variable "vault_hostname" {
  description = "The fully qualified domain name for Vault."
  type        = string
}

variable "metallb_ip_range" {
  description = "MetalLB IP address pool range."
  type        = string
}

variable "platform_core_repo_name" {
  description = "The name of the Gitea repository for platform core (terraform-managed)."
  type        = string
  default     = "platform-core"
}
