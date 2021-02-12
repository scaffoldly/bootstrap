variable "repository_name" {}
variable "stage_configs" {
  type = map(any)
}
variable "shared_env_vars" {
  type = map(any)
}

data "github_repository" "repository" {
  name = var.repository_name
}

resource "github_repository_file" "readme" {
  repository = var.repository_name
  branch     = data.github_repository.repository.default_branch
  file       = ".scaffoldly/README.md"

  content = <<EOF
Scaffoldly Config Files
=======================
*NOTE: DO NOT MANUALLY EDIT THESE FILES*

They are managed by Terraform and the Bootstrap project in your oganization.

They can be updated indirectly by adjusting the configuration in that project.

More info: https://docs.scaffold.ly
EOF

  commit_message = "[Scaffoldly] Update Readme"
  commit_author  = "Scaffoldly Bootstrap"
  commit_email   = "bootstrap@scaffold.ly"
}

resource "github_repository_file" "shared_env_vars" {
  repository = var.repository_name
  branch     = data.github_repository.repository.default_branch
  file       = ".scaffoldly/shared-env.json"

  content = jsonencode(var.shared_env_vars)

  commit_message = "[Scaffoldly] Update shared-env"
  commit_author  = "Scaffoldly Bootstrap"
  commit_email   = "bootstrap@scaffold.ly"
}

resource "github_repository_file" "services" {
  repository = data.github_repository.repository.name
  branch     = data.github_repository.repository.default_branch
  file       = ".scaffoldly/services.json"

  content = jsonencode(var.stage_configs)

  commit_message = "[Scaffoldly] Update service map"
  commit_author  = "Scaffoldly Bootstrap"
  commit_email   = "bootstrap@scaffold.ly"
}

module "stage_config_file" {
  source   = "./stage-config-file"
  for_each = var.stage_configs

  repository = data.github_repository.repository.name
  branch     = data.github_repository.repository.default_branch

  service_name = each.key
  stage_config = each.value
}