output "frontend_bucket_name"       { value = aws_s3_bucket.site.bucket }
output "cloudfront_domain_name"     { value = aws_cloudfront_distribution.cdn.domain_name }
output "cloudfront_distribution_id" { value = aws_cloudfront_distribution.cdn.id }
output "github_actions_role_arn"    { value = aws_iam_role.github_deploy.arn }


# 前端模块负责创建 GitHub OIDC Provider
# 输出它的 ARN，供其它模块（后端）复用
output "github_oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN (token.actions.githubusercontent.com)"
  # 若该模块用的是 count 索引，保持 [0]
  value       = aws_iam_openid_connect_provider.github[0].arn
}