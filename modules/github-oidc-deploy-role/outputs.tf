output "role_arn" {
  description = "ARN of the GitHub Actions deploy role."
  value       = aws_iam_role.deploy.arn
}

output "role_name" {
  description = "Name of the GitHub Actions deploy role."
  value       = aws_iam_role.deploy.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (created or pre-existing)."
  value       = local.provider_arn
}
