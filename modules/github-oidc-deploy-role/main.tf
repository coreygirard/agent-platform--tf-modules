# github-oidc-deploy-role
#
# The GitHub Actions OIDC provider + a scoped deploy role assumable only by one
# repo's branch via web identity (no static keys). This is the single source of
# truth for the OIDC thumbprint list (see variables.tf default).
#
# The role's *permissions* are the caller's responsibility — pass the scoped
# least-privilege policy as policy_json. The module owns only the trust
# relationship, so each service keeps its own narrow blast radius.

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.thumbprint_list
}

locals {
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : var.oidc_provider_arn
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repo}:ref:refs/heads/${var.branch}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  description          = coalesce(var.role_description, "Assumed by GitHub Actions in ${var.repo}@${var.branch} to deploy.")
  max_session_duration = var.max_session_duration
}

resource "aws_iam_role_policy" "scoped" {
  name   = "${var.role_name}-scoped"
  role   = aws_iam_role.deploy.id
  policy = var.policy_json
}
