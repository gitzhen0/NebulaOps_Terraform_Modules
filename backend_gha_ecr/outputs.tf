output "backend_gha_role_arn" {
  description = "GitHub Actions 用来 Assume 的 IAM Role ARN"
  value       = aws_iam_role.gha_push_ecr.arn
}

output "backend_ecr_repo_urls" {
  description = "Map: service -> ECR repository URL"
  value       = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}