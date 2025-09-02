locals {
  name_prefix = var.project_name
}

# ---------------- S3: Artifact Bucket ----------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifact_bucket_name
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# ---------------- ECR ----------------
resource "aws_ecr_repository" "this" {
  count                = var.create_ecr ? 1 : 0
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = var.tags
}

locals {
  ecr_repo_url = var.create_ecr ? aws_ecr_repository.this[0].repository_url : var.existing_ecr_repository_url
}

# ---------------- IAM: CodeBuild ----------------
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["codebuild.amazonaws.com"] }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.name_prefix}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild_inline" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    sid = "ECR"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "S3Artifacts"
    actions   = ["s3:GetObject","s3:PutObject","s3:GetObjectVersion","s3:GetBucketLocation","s3:ListBucket"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  # 可选：向 SSM 写入最新镜像
  dynamic "statement" {
    for_each = var.ssm_param_name == null ? [] : [1]
    content {
      sid       = "SSMParameter"
      actions   = ["ssm:PutParameter"]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "codebuild_inline" {
  role   = aws_iam_role.codebuild.id
  name   = "${local.name_prefix}-codebuild-inline"
  policy = data.aws_iam_policy_document.codebuild_inline.json
}

# ---------------- CodeBuild Project ----------------
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name_prefix}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_codebuild_project" "this" {
  name         = "${local.name_prefix}-build"
  description  = "Build & push Docker image to ECR"
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true # docker build in build container
    environment_variable {
      name  = "ECR_REPO_URL"
      value = local.ecr_repo_url
    }
    environment_variable {
      name  = "IMAGE_TAG_PREFIX"
      value = var.image_tag_prefix
    }
    environment_variable {
      name  = "SSM_PARAM_NAME"
      value = coalesce(var.ssm_param_name, "")
    }
    dynamic "environment_variable" {
      for_each = var.codebuild_env
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  logs_config {
    cloudwatch_logs { group_name = aws_cloudwatch_log_group.codebuild.name; stream_name = "build"; enabled = true }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-YAML
      version: 0.2
      env:
        shell: bash
      phases:
        pre_build:
          commands:
            - echo "Login to ECR"
            - aws --version
            - aws ecr get-login-password | docker login --username AWS --password-stdin "$(echo "$ECR_REPO_URL" | awk -F/ '{print $1}')"
            - COMMIT_SHA=${CODEBUILD_RESOLVED_SOURCE_VERSION:0:7}
            - IMAGE_TAG="${IMAGE_TAG_PREFIX}${COMMIT_SHA}"
            - echo "IMAGE_TAG=$IMAGE_TAG"
        build:
          commands:
            - echo "Build image"
            - docker build -t "$ECR_REPO_URL:$IMAGE_TAG" .
            - docker tag "$ECR_REPO_URL:$IMAGE_TAG" "$ECR_REPO_URL:latest"
        post_build:
          commands:
            - echo "Push image"
            - docker push "$ECR_REPO_URL:$IMAGE_TAG"
            - docker push "$ECR_REPO_URL:latest"
            - echo '{"imageUri":"'"$ECR_REPO_URL:$IMAGE_TAG"'"}' > imageDetail.json
            - |
              if [[ -n "$SSM_PARAM_NAME" ]]; then
                aws ssm put-parameter --name "$SSM_PARAM_NAME" --type String --value "$ECR_REPO_URL:$IMAGE_TAG" --overwrite
              fi
      artifacts:
        files:
          - imageDetail.json
    YAML
  }

  tags = var.tags
}

# ---------------- IAM: CodePipeline ----------------
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["codepipeline.amazonaws.com"] }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${local.name_prefix}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codepipeline_inline" {
  statement {
    sid = "S3"
    actions = ["s3:PutObject","s3:GetObject","s3:GetObjectVersion","s3:GetBucketVersioning","s3:ListBucket"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  statement {
    sid       = "CodeBuild"
    actions   = ["codebuild:BatchGetBuilds","codebuild:StartBuild"]
    resources = [aws_codebuild_project.this.arn]
  }

  statement {
    sid       = "CodeStarConnection"
    actions   = ["codestar-connections:UseConnection"]
    resources = [var.github_connection_arn]
  }

  # CloudWatch Events/Logs 等（宽松一些，便于通知/触发）
  statement {
    sid       = "CloudWatchEvents"
    actions   = ["events:Put*","events:Describe*","events:List*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline_inline" {
  role   = aws_iam_role.codepipeline.id
  name   = "${local.name_prefix}-codepipeline-inline"
  policy = data.aws_iam_policy_document.codepipeline_inline.json
}

# ---------------- CodePipeline ----------------
resource "aws_codepipeline" "this" {
  name     = "${local.name_prefix}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = var.github_connection_arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAndPushImage"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.this.name
      }
    }
  }

  tags = var.tags
}

# 便于从外部看最近一次构建的 image
resource "aws_ssm_parameter" "image_uri_hint" {
  count = var.ssm_param_name == null ? 0 : 1
  name  = var.ssm_param_name
  type  = "String"
  value = ""
  tags  = var.tags
}