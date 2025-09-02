variable "backend_aws_region" {
    description = "AWS region"
    type = string 
}

# GitHub via CodeStar Connections（先在控制台创建连接，拿 ARN）
variable "backend_github_connection_arn" { type = string }
variable "backend_github_owner"  { type = string }
variable "backend_github_repo"   { type = string }
variable "backend_github_branch" { type = string }

# Pipeline artifact bucket（需全局唯一）
variable "backend_artifact_bucket_name" { type = string }

# 微服务列表（与代码目录名一致，顶层目录，如 users-service）
variable "backend_service_names" {
  type    = list(string)
  default = ["api-gateway","users-service","orders-service","inventory-service"]
}

# 生成 ECR 仓库名：<prefix>/<service>
variable "backend_ecr_repo_prefix" {
  type    = string
  default = "microshop"
}

# 命名前缀（环境/项目名）
variable "backend_project_name" {
  type    = string
  default = "dev"
}

variable "backend_codebuild_compute_type" {
  type    = string
  default = "BUILD_GENERAL1_SMALL"
}

variable "backend_codebuild_image" {
  type    = string
  default = "aws/codebuild/standard:7.0"
}