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
