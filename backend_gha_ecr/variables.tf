variable "backend_aws_region" {
  description = "AWS region"
  type        = string
}

# GitHub 仓库（用于 OIDC 信任条件）
variable "backend_github_owner"  { type = string } # 例如 gitzhen0
variable "backend_github_repo"   { type = string } # 例如 microshop_backend
variable "backend_github_branch" { type = string } # 例如 main

# 是否在此模块内创建 GitHub OIDC Provider（如果账户里已有，可设为 false 并传入现有 ARN）
variable "backend_create_oidc_provider" {
  type    = bool
  default = true
}

variable "backend_existing_oidc_provider_arn" {
  type        = string
  default     = ""
  description = "已有 OIDC Provider ARN（backend_create_oidc_provider=false 时必填）"
}

# 要创建的 ECR 仓库（默认四个微服务）
variable "backend_service_names" {
  type        = list(string)
  default     = ["api-gateway", "users-service", "orders-service", "inventory-service"]
}

variable "backend_ecr_repo_prefix" {
  description = "ECR repo 前缀，最终为 <prefix>/<service>"
  type        = string
  default     = "microshop"
}

# 命名前缀（可放 env 名称，如 dev / prod）
variable "backend_project_name" {
  type    = string
  default = "dev"
}