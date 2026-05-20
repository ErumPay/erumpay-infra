variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnets" {
  type = list(string)
}

variable "azs" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "db_username" {
  description = "DB 관리자 계정"
  type        = string
}

variable "db_password" {
  description = "DB 비밀번호"
  type        = string
  sensitive   = true
}