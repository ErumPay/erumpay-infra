# rds 모듈, helm 배포 시 클러스터 이름 참조용
output "cluster_name" {
  value = aws_eks_cluster.main.name
}

# kubectl 설정할 때 사용
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
