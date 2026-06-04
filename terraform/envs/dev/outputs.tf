output "cluster_name" {
  description = "EKS cluster name used by aws eks update-kubeconfig and Helm releases."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = module.eks.cluster_endpoint
}

output "aws_region" {
  description = "AWS region for the dev environment."
  value       = "ap-northeast-2"
}

output "external_secrets_role_arn" {
  description = "IAM role ARN used by the External Secrets Operator service account."
  value       = aws_iam_role.external_secrets.arn
}
