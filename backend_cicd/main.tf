terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" { region = var.backend_aws_region }

# ---------------- S3: Artifact Bucket ----------------
resource "aws_s3_bucket" "artifacts" {
  bucket = var.backend_artifact_bucket_name
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------- ECR repos（每服务一个） ----------------
locals { services = var.backend_service_names }

resource "aws_ecr_repository" "svc" {
  for_each             = toset(local.services)
  name                 = "${var.backend_ecr_repo_prefix}/${each.key}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

locals {
  ecr_repo_urls = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}

# ---------------- IAM: CodeBuild ----------------
data "aws_iam_policy_document" "cb_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { 
        type = "Service"
        identifiers = ["codebuild.amazonaws.com"] 
    }
  }
}

resource "aws_iam_role" "codebuild_role" {
  name               = "${var.backend_project_name}-cb-role"
  assume_role_policy = data.aws_iam_policy_document.cb_assume.json
}

data "aws_iam_policy_document" "cb_policy" {
  statement {
    sid     = "ECRPushPull"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability","ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart","ecr:InitiateLayerUpload","ecr:PutImage",
      "ecr:BatchGetImage","ecr:GetDownloadUrlForLayer","ecr:DescribeRepositories"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "S3Artifacts"
    actions = ["s3:GetObject","s3:PutObject","s3:PutObjectAcl","s3:GetBucketLocation","s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn,"${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid     = "Logs"
    actions = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    sid     = "STS"
    actions = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild_inline" {
  role   = aws_iam_role.codebuild_role.id
  name   = "${var.backend_project_name}-cb-policy"
  policy = data.aws_iam_policy_document.cb_policy.json
}

# ---------------- CodeBuild Project ----------------
resource "aws_codebuild_project" "build" {
  name         = "${var.backend_project_name}-backend-build"
  description  = "Build & push microservices images to ECR"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = var.backend_codebuild_compute_type
    image           = var.backend_codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = true   # 允许 docker build

    environment_variable {
        name  = "BACKEND_SERVICE_NAMES"
        value = join(",", var.backend_service_names)
    }
    environment_variable {
        name  = "ECR_REPOS_JSON"
        value = jsonencode(local.ecr_repo_urls)
    }
    environment_variable {
        name  = "AWS_DEFAULT_REGION"
        value = var.backend_aws_region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = templatefile("${path.module}/buildspec.yml.tmpl", {})
  }

  logs_config {
  cloudwatch_logs {
    group_name  = "/codebuild/${var.backend_project_name}-backend-build"
    stream_name = "build"
  }
}

queued_timeout = 60
}

# ---------------- IAM: CodePipeline ----------------
data "aws_iam_policy_document" "cp_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { 
        type = "Service"
        identifiers = ["codepipeline.amazonaws.com"] 
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "${var.backend_project_name}-cp-role"
  assume_role_policy = data.aws_iam_policy_document.cp_assume.json
}

data "aws_iam_policy_document" "cp_policy" {
  statement {
    sid     = "S3Artifacts"
    actions = ["s3:GetObject","s3:GetObjectVersion","s3:PutObject","s3:PutObjectAcl","s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn,"${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "StartBuild"
    actions   = ["codebuild:BatchGetBuilds","codebuild:StartBuild"]
    resources = [aws_codebuild_project.build.arn]
  }

  statement {
    sid       = "UseConnection"
    actions   = ["codestar-connections:UseConnection"]
    resources = [var.backend_github_connection_arn]
  }
}

resource "aws_iam_role_policy" "codepipeline_inline" {
  role   = aws_iam_role.codepipeline_role.id
  name   = "${var.backend_project_name}-cp-policy"
  policy = data.aws_iam_policy_document.cp_policy.json
}

# ---------------- CodePipeline ----------------
resource "aws_codepipeline" "pipeline" {
  name     = "${var.backend_project_name}-backend-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = var.backend_github_connection_arn
        FullRepositoryId = "${var.backend_github_owner}/${var.backend_github_repo}"
        BranchName       = var.backend_github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "CodeBuild_Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }
}