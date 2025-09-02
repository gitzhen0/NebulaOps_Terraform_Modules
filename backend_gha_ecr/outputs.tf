output "backend_gha_role_arn" {
  description = "GitHub Actions 用来 Assume 的 IAM 角色 ARN"
  value       = aws_iam_role.gha_ecr_role.arn
}

output "backend_ecr_repo_urls" {
  description = "Map: service -> ECR repository URL"
  value       = local.ecr_repo_urls
}

output "backend_oidc_provider_arn" {
  value = local.oidc_provider_arn
}