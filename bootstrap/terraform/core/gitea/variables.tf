variable "gitea_chart_version" {
  description = "The version of the Gitea Helm chart to deploy."
  type        = string
  default     = "12.4.0"
}

variable "hostname" {
  description = "The fully qualified domain name for the application ingress."
  type        = string
}

variable "ssh_hostname" {
  description = "The fully qualified domain name for the SSH clone endpoint."
  type        = string
}

variable "ssh_loadbalancer_ip" {
  description = "The dedicated LoadBalancer IP for the Gitea SSH service."
  type        = string
}

variable "ssh_allowed_sources" {
  description = "Optional source CIDR allowlist for the Gitea SSH LoadBalancer service."
  type        = list(string)
  default     = []
}

variable "namespace" {
  description = "The namespace the application is deployed into."
  type        = string
  default     = "gitea"
}

variable "admin_username" {
  description = "The username of the Gitea admin account"
  type        = string
}

variable "admin_email" {
  description = "The email of the Gitea admin account"
  type        = string
}
