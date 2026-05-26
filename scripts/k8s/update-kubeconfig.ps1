param(
    [string]$ClusterName = "erumpay-eks-cluster",
    [string]$Region = "ap-northeast-2",
    [string]$Alias = "erumpay-dev"
)

$ErrorActionPreference = "Stop"

aws sts get-caller-identity
aws eks update-kubeconfig --region $Region --name $ClusterName --alias $Alias
kubectl config use-context $Alias
kubectl get nodes
