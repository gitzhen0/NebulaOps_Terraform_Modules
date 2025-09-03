terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region = var.backend_aws_region
}

locals {
  services   = var.backend_service_names
  repo_names = [for s in local.services : "${var.backend_ecr_repo_prefix}/${s}"]
}

# ---- GitHub OIDC Provider（可选创建） ----
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.backend_create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub OIDC CA
}

locals {
  oidc_provider_arn = var.backend_create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.backend_existing_oidc_provider_arn
}

# ---- IAM Role 给 GitHub Actions 假设（OIDC）----
data "aws_iam_policy_document" "gha_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # 限制到具体仓库 + 分支
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.backend_github_owner}/${var.backend_github_repo}:ref:refs/heads/${var.backend_github_branch}"]
    }
  }
}

resource "aws_iam_role" "gha_push_ecr" {
  name               = "${var.backend_project_name}-backend-gha-ecr-role"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
}

# ---- ECR 仓库们 ----
resource "aws_ecr_repository" "svc" {
  for_each             = toset(local.services)
  name                 = "${var.backend_ecr_repo_prefix}/${each.key}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

# ---- 允许此角色 Push / Pull 到上述 ECR ----
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid     = "AuthToken"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrRepoScoped"
    actions = [
      "ecr:BatchCheckLayerAvailability","ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart","ecr:InitiateLayerUpload","ecr:PutImage",
      "ecr:BatchGetImage","ecr:GetDownloadUrlForLayer","ecr:DescribeRepositories",
      "ecr:ListImages","ecr:DescribeImages","ecr:BatchDeleteImage"
    ]
    resources = [for r in aws_ecr_repository.svc : r.arn]
  }

  statement {
    sid     = "StsRead"
    actions = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecr_push_inline" {
  role   = aws_iam_role.gha_push_ecr.id
  name   = "${var.backend_project_name}-backend-gha-ecr-policy"
  policy = data.aws_iam_policy_document.ecr_push.json
}