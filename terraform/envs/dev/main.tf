module "vpc" {
  source          = "../../modules/vpc"
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  azs             = var.azs
}

# vpc 모듈에서 만든 vpc_id를 security 모듈에 전달
module "security" {
  source = "../../modules/security"
  vpc_id = module.vpc.vpc_id
}

# vpc/security 모듈 output을 eks 모듈에 전달
module "eks" {
  source             = "../../modules/eks"
  private_subnet_ids = module.vpc.private_subnet_ids
  eks_cluster_sg_id  = module.security.eks_cluster_sg_id
}

# vpc/security 모듈 output을 rds 모듈에 전달
module "rds" {
  source             = "../../modules/rds"
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security.rds_sg_id
  db_username        = var.db_username
  db_password        = var.db_password
}

resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_eks_cluster" {
  security_group_id            = module.security.rds_sg_id
  referenced_security_group_id = module.eks.cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "Allow MySQL from EKS cluster security group"
}

module "ecr" {
  source = "../../modules/ecr"
}

data "aws_caller_identity" "current" {}

data "tls_certificate" "eks_oidc" {
  url = module.eks.oidc_issuer_url
}

locals {
  aws_region              = "ap-northeast-2"
  external_secrets_sa     = "external-secrets"
  external_secrets_ns     = "platform-operations"
  external_secrets_secret = "erumpay/dev/all"
  ebs_csi_sa              = "ebs-csi-controller-sa"
  ebs_csi_ns              = "kube-system"
  // [infra] 나영은 260609 1533 | ALB Controller IRSA trust policy에서 허용할 Kubernetes ServiceAccount를 고정한다.
  alb_controller_sa      = "aws-load-balancer-controller"
  alb_controller_ns      = "kube-system"
  oidc_provider_hostpath = replace(module.eks.oidc_issuer_url, "https://", "")
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = module.eks.oidc_issuer_url

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint
  ]
}

resource "aws_iam_policy" "external_secrets" {
  name = "erumpay-external-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${local.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.external_secrets_secret}-*"
      }
    ]
  })
}

resource "aws_iam_role" "external_secrets" {
  name = "erumpay-external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_hostpath}:aud" = "sts.amazonaws.com"
            "${local.oidc_provider_hostpath}:sub" = "system:serviceaccount:${local.external_secrets_ns}:${local.external_secrets_sa}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

resource "aws_iam_role" "ebs_csi" {
  name = "erumpay-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_hostpath}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_hostpath}:sub" = "system:serviceaccount:${local.ebs_csi_ns}:${local.ebs_csi_sa}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

// [infra] 나영은 260609 1533 | aws-load-balancer-controller가 ALB, listener, target group, security group을 관리할 수 있는 IAM policy를 Terraform 상태로 관리한다.
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/aws-load-balancer-controller-iam-policy.json")
}

// [infra] 나영은 260609 1533 | kube-system/aws-load-balancer-controller ServiceAccount가 OIDC 기반으로 AssumeRole 할 수 있는 IRSA role이다.
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "AmazonEKSLoadBalancerControllerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_hostpath}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_hostpath}:sub" = "system:serviceaccount:${local.alb_controller_ns}:${local.alb_controller_sa}"
        }
      }
    }]
  })
}

// [infra] 나영은 260609 1533 | ALB Controller IRSA role에 AWS 리소스 관리 권한 policy를 연결한다.
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
    module.eks
  ]
}

resource "null_resource" "gp2_default_storageclass" {
  triggers = {
    cluster_name = module.eks.cluster_name
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "aws eks update-kubeconfig --region ap-northeast-2 --name ${module.eks.cluster_name} && kubectl patch storageclass gp2 -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"
  }

  depends_on = [module.eks]
}
