variable "hostname" {
  description = "The fully qualified domain name for the application ingress."
  type        = string
}

variable "namespace" {
  description = "The namespace the application is deployed into."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "The version of the ArgoCD Helm chart to deploy."
  type        = string
  default     = "8.0.17"
}