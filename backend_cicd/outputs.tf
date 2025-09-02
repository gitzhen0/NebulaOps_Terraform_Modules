output "backend_pipeline_name"   { value = aws_codepipeline.pipeline.name }
output "backend_codebuild_name"  { value = aws_codebuild_project.build.name }
output "backend_artifact_bucket" { value = aws_s3_bucket.artifacts.bucket }
output "backend_ecr_repo_urls" {
  description = "Map(service -> ECR repo url)"
  value       = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}