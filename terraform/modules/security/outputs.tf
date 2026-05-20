# eks 모듈이 클러스터 만들 때 사용
output "eks_cluster_sg_id" {
  value = aws_security_group.eks_cluster.id
}

# eks 모듈이 노드그룹 만들 때 사용
output "eks_nodes_sg_id" {
  value = aws_security_group.eks_nodes.id
}

# rds 모듈이 인스턴스 만들 때 사용
output "rds_sg_id" {
  value = aws_security_group.rds.id
}