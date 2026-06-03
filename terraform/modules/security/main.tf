# EKS 클러스터 보안그룹
# EKS Control Plane이 외부와 통신할 때 사용
resource "aws_security_group" "eks_cluster" {
  name        = "erumpay-eks-cluster-sg"
  description = "EKS Cluster Security Group"
  vpc_id      = var.vpc_id

  # HTTPS 인바운드 (kubectl, ALB → EKS)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 허용 (EKS → 외부)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "erumpay-eks-cluster-sg" }
}

# EKS 워커노드 보안그룹
# 실제 pod들이 떠있는 EC2 노드용
resource "aws_security_group" "eks_nodes" {
  name        = "erumpay-eks-nodes-sg"
  description = "EKS Node Group Security Group"
  vpc_id      = var.vpc_id

  # 노드끼리 통신 (같은 보안그룹 내)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Control Plane → 노드 통신
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # 모든 아웃바운드 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "erumpay-eks-nodes-sg" }
}

# RDS 보안그룹
# EKS 노드에서만 MySQL 접근 가능하도록 제한
resource "aws_security_group" "rds" {
  name        = "erumpay-rds-sg"
  description = "RDS Security Group"
  vpc_id      = var.vpc_id

  tags = { Name = "erumpay-rds-sg" }
}
