terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region = var.backend_aws_region
}

locals {
  services        = var.backend_service_names
  default_subject = "repo:${var.backend_github_owner}/${var.backend_github_repo}:ref:refs/heads/${var.backend_github_branch}"
  allowed_subjects = length(var.backend_allowed_subjects) > 0 ? var.backend_allowed_subjects : [local.default_subject]
}

# -------- GitHub OIDC Provider（可选择创建） --------
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.backend_create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub OIDC 根证书指纹（DigiCert Global Root G2）
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  oidc_provider_arn = var.backend_create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.backend_oidc_provider_arn
}

# -------- ECR 仓库 --------
resource "aws_ecr_repository" "svc" {
  for_each             = toset(local.services)
  name                 = "${var.backend_ecr_repo_prefix}/${each.key}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

locals {
  ecr_repo_arns = { for k, r in aws_ecr_repository.svc : k => r.arn }
  ecr_repo_urls = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}

# -------- GitHub Actions Assume 的 IAM 角色 --------
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
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_subjects
    }
  }
}

resource "aws_iam_role" "gha_ecr_role" {
  name               = "${var.backend_project_name}-gha-ecr-role"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
}

# 仅限于推送到我们创建的这些 ECR 仓库
data "aws_iam_policy_document" "gha_ecr_policy" {
  statement {
    sid     = "ECRGetAuth"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid     = "ECRPushPullSpecificRepos"
    actions = [
      "ecr:BatchCheckLayerAvailability","ecr:CompleteLayerUpload","ecr:UploadLayerPart",
      "ecr:InitiateLayerUpload","ecr:PutImage","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer",
      "ecr:DescribeRepositories","ecr:ListImages"
    ]
    resources = values(local.ecr_repo_arns)
  }
  statement {
    sid     = "STSCallerIdentity"
    actions = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "gha_ecr_inline" {
  role   = aws_iam_role.gha_ecr_role.id
  name   = "${var.backend_project_name}-gha-ecr-policy"
  policy = data.aws_iam_policy_document.gha_ecr_policy.json
}