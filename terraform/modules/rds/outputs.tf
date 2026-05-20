# 나중에 애플리케이션 설정에서 참조
output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}