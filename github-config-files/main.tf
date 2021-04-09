terraform {
  required_version = ">= 0.14"
}

variable "organization" {
  type = string
}
variable "repository_name" {
  type = string
}
variable "stages" {
  type = list(string)
}
variable "stage_urls" {
  type = map(any) # TODO Figure out proper type
}
variable "shared_env_vars" {
  type = map(string)
}

data "github_repository" "repository" {
  full_name = "${var.organization}/${var.repository_name}"
}

resource "github_repository_file" "readme" {
  repository = "${var.organization}/${var.repository_name}"
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

  overwrite_on_create = true

  lifecycle {
    ignore_changes = [
      branch
    ]
  }
}

module "stage_files" {
  count  = length(var.stages)
  source = "./stage-files"

  organization    = var.organization
  repository_name = var.repository_name
  branch          = data.github_repository.repository.default_branch

  stage_name = var.stages[count.index]

  stage_urls = {
    for key, value in var.stage_urls :
    key => lookup(value, var.stages[count.index], "unknown-url")
  }

  shared_env_vars = var.shared_env_vars
}

module "stage_files_default" {
  source = "./stage-files"

  organization    = var.organization
  repository_name = var.repository_name
  branch          = data.github_repository.repository.default_branch

  stage_name = ""

  stage_urls = {
    for key, value in var.stage_urls :
    key => lookup(value, "nonlive", "unknown-url") # TODO: Configurable default stage
  }

  shared_env_vars = var.shared_env_vars
}
