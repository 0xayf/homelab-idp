variable "gitea_chart_version" {
  description = "The version of the Gitea Helm chart to deploy."
  type        = string
  default     = "12.1.1"
}

variable "hostname" {
  description = "The fully qualified domain name for the application ingress."
  type        = string
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