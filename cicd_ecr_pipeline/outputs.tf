output "pipeline_name" {
  value       = aws_codepipeline.this.name
  description = "CodePipeline 名称"
}

output "codebuild_project_name" {
  value       = aws_codebuild_project.this.name
  description = "CodeBuild 项目名"
}

output "artifact_bucket" {
  value       = aws_s3_bucket.artifacts.bucket
  description = "Artifact S3 bucket"
}

output "ecr_repository_url" {
  value       = local.ecr_repo_url
  description = "ECR 仓库 URL"
}

output "ssm_param_name" {
  value       = var.ssm_param_name
  description = "写入镜像URI的 SSM 参数名（如设置）"
}