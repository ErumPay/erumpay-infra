# 서비스별 ECR 리포지토리
# Jenkins CI에서 이미지 빌드 후 여기에 push
locals {
  repositories = [
    "erumpay/auth-service",
    "erumpay/card-service",
    "erumpay/payment-service",
    "erumpay/recommendation-service",
    "erumpay/notification-service",
    "erumpay/api-gateway",
    "erumpay/pg-auth-service",
    "erumpay/billing-key-service",
    "erumpay/pg-payment-service",
    "erumpay/merchant-service",
    "erumpay/card-simulator-service",
    "erumpay/mobile-app",
    "erumpay/web-client",
    "erumpay/erumpay-infra"
  ]
}

resource "aws_ecr_repository" "main" {
  for_each = toset(local.repositories)

  name                 = each.value
  # 이미지 덮어쓰기 허용 (같은 태그로 재배포 가능)
  image_tag_mutability = "MUTABLE"

  # 이미지 취약점 스캔 (push 시 자동 실행)
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = each.value }
}