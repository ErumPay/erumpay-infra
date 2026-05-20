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