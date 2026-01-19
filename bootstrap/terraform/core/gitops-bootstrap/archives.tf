data "archive_file" "platform_apps" {
  type        = "zip"
  source_dir  = var.platform_apps_path
  output_path = "${path.module}/.generated/platform-apps.zip"
  excludes    = [".git", ".DS_Store"]
}

data "archive_file" "platform_core" {
  type        = "zip"
  source_dir  = var.platform_core_path
  output_path = "${path.module}/.generated/platform-core.zip"
  excludes = [
    ".terraform",
    ".terraform.lock.hcl",
    "terraform.tfstate",
    "terraform.tfstate.backup",
    "*.tfstate*",
    "core/gitops-bootstrap",
    "bootstrap.auto.tfvars",
    "bootstrap.tf",
    "providers-bootstrap.tf",
    "variables-bootstrap.tf",
    ".git",
    "__pycache__",
    ".DS_Store",
    ".generated"
  ]
}

data "local_file" "platform_apps_archive" {
  filename   = data.archive_file.platform_apps.output_path
  depends_on = [data.archive_file.platform_apps]
}

data "local_file" "platform_core_archive" {
  filename   = data.archive_file.platform_core.output_path
  depends_on = [data.archive_file.platform_core]
}

resource "kubernetes_config_map_v1" "platform_apps_archive" {
  metadata {
    name      = "platform-apps-archive"
    namespace = var.gitea_namespace
  }
  binary_data = {
    "platform-apps.zip" = data.local_file.platform_apps_archive.content_base64
  }
}

resource "kubernetes_config_map_v1" "platform_core_archive" {
  metadata {
    name      = "platform-core-archive"
    namespace = var.gitea_namespace
  }
  binary_data = {
    "platform-core.zip" = data.local_file.platform_core_archive.content_base64
  }
}
