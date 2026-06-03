# vpc 모듈 output에서 받아옴
variable "private_subnet_ids" {
  description = "Private Subnet ID 목록"
  type        = list(string)
}

# security 모듈 output에서 받아옴
variable "rds_sg_id" {
  description = "RDS 보안그룹 ID"
  type        = string
}

# terraform.tfvars에서 받아옴 (git 제외)
variable "db_username" {
  description = "DB 관리자 계정"
  type        = string
}

variable "db_password" {
  description = "DB 비밀번호"
  type        = string
  sensitive   = true # plan/apply 출력에서 마스킹됨
}