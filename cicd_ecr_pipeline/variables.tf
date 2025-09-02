variable "project_name" {
  description = "项目名（用于命名前缀）"
  type        = string
}

variable "artifact_bucket_name" {
  description = "CodePipeline Artifact S3 bucket 名（全局唯一，建议外部约定好）"
  type        = string
}

variable "github_connection_arn" {
  description = "AWS CodeStar Connections 连接 ARN（GitHub OAuth 需手动在控制台授权一次）"
  type        = string
}

variable "github_owner" { description = "GitHub 组织/用户"; type = string }
variable "github_repo"  { description = "GitHub 仓库名";   type = string }
variable "github_branch"{
  description = "构建分支"
  type        = string
  default     = "main"
}

variable "create_ecr" {
  description = "是否创建 ECR 仓库（true=创建；false=使用 existing_ecr_repository_url）"
  type        = bool
  default     = true
}

variable "ecr_repo_name" {
  description = "ECR 仓库名（当 create_ecr=true 时必填）"
  type        = string
  default     = null
}

variable "existing_ecr_repository_url" {
  description = "已存在的 ECR 仓库 URL（当 create_ecr=false 时必填，形如 xxxxx.dkr.ecr.us-east-1.amazonaws.com/my-repo）"
  type        = string
  default     = null
}

variable "ssm_param_name" {
  description = "可选：把最新镜像URI写入的 SSM 参数名（例如 /microshop/backend/image_uri）"
  type        = string
  default     = null
}

variable "codebuild_compute_type" {
  description = "CODEBUILD 机器规格"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "image_tag_prefix" {
  description = "可选：镜像 tag 前缀（例如 env- 或 svc-）"
  type        = string
  default     = ""
}

variable "codebuild_env" {
  description = "附加到 CodeBuild 的环境变量（明文）"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}