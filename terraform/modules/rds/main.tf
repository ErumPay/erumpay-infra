# RDS가 배치될 서브넷 그룹 (Private Subnet 2개)
resource "aws_db_subnet_group" "main" {
  name       = "erumpay-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "erumpay-rds-subnet-group" }
}

# MySQL RDS 인스턴스
resource "aws_db_instance" "main" {
  identifier        = "erumpay-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = "erumpay"
  username = var.db_username
  password = var.db_password

  # Private Subnet에 배치
  db_subnet_group_name = aws_db_subnet_group.main.name
  # EKS 노드에서만 접근 가능
  vpc_security_group_ids = [var.rds_sg_id]

  # 외부에서 직접 접근 불가
  publicly_accessible = false
  # 데모 환경이라 최종 스냅샷 생략
  skip_final_snapshot = true

  tags = { Name = "erumpay-mysql" }
}