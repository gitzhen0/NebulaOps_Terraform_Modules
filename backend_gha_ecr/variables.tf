variable "backend_aws_region" {
  description = "AWS region"
  type        = string
}

# GitHub 仓库（发起 Actions 的后端 repo）
variable "backend_github_owner"  { type = string }
variable "backend_github_repo"   { type = string }
variable "backend_github_branch" { type = string }

# 要创建的 ECR 仓库（一个服务一个仓库）
variable "backend_service_names" {
  description = "微服务目录名列表（与 repo 中的模块目录一致）"
  type        = list(string)
  default     = ["api-gateway", "users-service", "orders-service", "inventory-service"]
}

variable "backend_ecr_repo_prefix" {
  description = "ECR 仓库前缀，最终名为 <prefix>/<service>"
  type        = string
  default     = "microshop"
}

# 是否由本模块创建 GitHub OIDC Provider（一个账户一般只需要建一次）
variable "backend_create_oidc_provider" {
  type    = bool
  default = true
}

# 若账户里已存在 GitHub OIDC Provider，可把 ARN 传进来并把上面开关设为 false
variable "backend_oidc_provider_arn" {
  type    = string
  default = ""
}

# 允许的 subject（可留空用默认：限定某个分支）
variable "backend_allowed_subjects" {
  description = "可 AssumeRole 的 GitHub OIDC subject 列表"
  type        = list(string)
  default     = []
}

variable "backend_project_name" {
  description = "命名前缀（如 dev / prod）"
  type        = string
  default     = "dev"
}