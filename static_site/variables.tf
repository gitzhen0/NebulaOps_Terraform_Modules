variable "domain_name"    { type = string }
variable "hosted_zone_id" { type = string }

variable "frontend_github_owner"   { type = string }  # e.g., "gitzhen0"
variable "frontend_github_repo"    { type = string }  # e.g., "microshop_frontend"
variable "frontend_github_branch" {
  type    = string
  default = "main"
}

# 账户里若已存在 GitHub OIDC Provider，可设 false 复用
variable "frontend_create_github_oidc_provider" { 
    type = bool 
    default = true 
}

variable "frontend_force_destroy_bucket" {
    type = bool
    default = false
}