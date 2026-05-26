# KAN-1286 kubectl connection

## Goal

Connect local `kubectl` to the dev EKS cluster.

## Prerequisites

- AWS CLI is installed.
- AWS credentials are configured for the ErumPay AWS account.
- `kubectl` is installed.
- Terraform dev environment has been applied.

## Current cluster values

```text
region: ap-northeast-2
cluster_name: erumpay-eks-cluster
```

You can also confirm the Terraform outputs:

```bash
cd terraform/envs/dev
terraform output cluster_name
terraform output aws_region
```

## Connect

```bash
aws sts get-caller-identity
aws eks update-kubeconfig --region ap-northeast-2 --name erumpay-eks-cluster --alias erumpay-dev
kubectl config use-context erumpay-dev
kubectl cluster-info
kubectl get nodes
```

## Troubleshooting

If `kubectl` says the kubeconfig file is denied, move the existing file and regenerate it.

PowerShell:

```powershell
New-Item -ItemType Directory -Force $env:USERPROFILE\.kube
Rename-Item $env:USERPROFILE\.kube\config config.backup -ErrorAction SilentlyContinue
aws eks update-kubeconfig --region ap-northeast-2 --name erumpay-eks-cluster --alias erumpay-dev
```

If AWS credentials are missing:

```bash
aws configure sso
# or use the team-approved credential setup
aws sts get-caller-identity
```
