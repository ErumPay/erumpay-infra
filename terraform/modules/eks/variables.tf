# vpc 모듈 output에서 받아옴
variable "private_subnet_ids" {
  description = "Private Subnet ID 목록 (EKS 노드 배치용)"
  type        = list(string)
}

# security 모듈 output에서 받아옴
variable "eks_cluster_sg_id" {
  description = "EKS 클러스터 보안그룹 ID"
  type        = string
}