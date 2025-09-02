# cicd-ecr-pipeline

- Source: GitHub (CodeStar Connections)
- Build: CodeBuild (Docker build, push to ECR)
- Store: CodePipeline Artifacts (S3)
- Optional: Write latest image URI to SSM Parameter

## Inputs
- github_connection_arn: 在控制台授权一次 GitHub 连接，填 ARN
- artifact_bucket_name: 需全局唯一
- create_ecr=true 时提供 ecr_repo_name；否则提供 existing_ecr_repository_url

## Outputs
- pipeline_name, codebuild_project_name, ecr_repository_url, artifact_bucket, ssm_param_name