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

// [infra] 나영은 260609 1533 | Helm values나 ServiceAccount annotation에 사용할 ALB Controller IRSA role ARN을 노출한다.
output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN used by the aws-load-balancer-controller service account."
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "route53_zone_id" {
  description = "Route53 public hosted zone ID for eunna.store."
  value       = aws_route53_zone.public.zone_id
}

output "route53_name_servers" {
  description = "Name servers to delegate from Gabia for eunna.store."
  value       = aws_route53_zone.public.name_servers
}

output "api_acm_certificate_arn" {
  description = "ACM certificate ARN for api.eunna.store."
  value       = aws_acm_certificate.api.arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN used by the external-dns service account."
  value       = aws_iam_role.external_dns.arn
}
