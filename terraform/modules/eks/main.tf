# EKS 클러스터가 AWS 서비스 호출할 때 사용하는 IAM 역할
resource "aws_iam_role" "eks_cluster" {
  name = "erumpay-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

# EKS 클러스터 동작에 필요한 기본 정책 연결
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS 클러스터 생성
resource "aws_eks_cluster" "main" {
  name     = "erumpay-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.29"

  vpc_config {
    # Private Subnet에 클러스터 배치
    subnet_ids         = var.private_subnet_ids
    # EKS 클러스터 보안그룹 연결
    security_group_ids = [var.eks_cluster_sg_id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# 워커노드가 EKS에 조인할 때 사용하는 IAM 역할
resource "aws_iam_role" "node_group" {
  name = "erumpay-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 워커노드에 필요한 3가지 정책 연결
# - EKSWorkerNodePolicy: 노드가 클러스터에 조인
# - EKS_CNI_Policy: pod 네트워크 설정
# - ECRReadOnly: ECR에서 이미지 pull
resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])
  policy_arn = each.value
  role       = aws_iam_role.node_group.name
}

# namespace별 노드그룹 정의
# pay/pg 각 2개, middleware/observability 각 1개 = 총 6개
locals {
  node_groups = {
    pay = {
      desired = 2
      min     = 1
      max     = 3
    }
    pg = {
      desired = 2
      min     = 1
      max     = 3
    }
    middleware = {
      desired = 1
      min     = 1
      max     = 2
    }
    observability = {
      desired = 1
      min     = 1
      max     = 2
    }
  }
}

# 각 namespace별 노드그룹 생성
resource "aws_eks_node_group" "main" {
  for_each = local.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "erumpay-${each.key}"
  node_role_arn   = aws_iam_role.node_group.arn

  # Private Subnet에 노드 배치
  subnet_ids     = var.private_subnet_ids
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = each.value.desired
    min_size     = each.value.min
    max_size     = each.value.max
  }

  # 노드에 namespace 라벨 붙이기 (pod 스케줄링에 사용)
  labels = { role = each.key }

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}