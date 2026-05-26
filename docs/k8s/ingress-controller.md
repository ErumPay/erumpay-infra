# KAN-1279 Ingress Controller

## Controller

Use AWS Load Balancer Controller for EKS ALB ingress.

AWS official install flow:

1. Create IAM policy for the controller.
2. Create a Kubernetes service account with IAM permissions.
3. Install the Helm chart from `https://aws.github.io/eks-charts`.
4. Verify the controller deployment in `kube-system`.

## Required tools

- `kubectl`
- `helm`
- `eksctl`
- AWS CLI credentials

## Install

Run after KAN-1286 is complete:

PowerShell one-shot:

```powershell
.\scripts\k8s\install-aws-load-balancer-controller.ps1
```

Manual equivalent:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=erumpay-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 \
  --set vpcId=<VPC_ID>
```

## Verify

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## Notes

The service account needs IAM permissions before installing the chart. Create it with the team-approved IAM policy process or `eksctl create iamserviceaccount`.
