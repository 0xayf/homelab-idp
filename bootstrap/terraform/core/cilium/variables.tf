variable "namespace" {
  description = "The namespace the application is deployed into."
  type        = string
  default     = "cilium"
}

variable "cilium_chart_version" {
  description = "The version of the Cilium Helm chart to deploy."
  type        = string
  default     = "1.18.5"
}
