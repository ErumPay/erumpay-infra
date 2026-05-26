param(
    [string]$ClusterName = "erumpay-eks-cluster",
    [string]$Region = "ap-northeast-2",
    [string]$ContextAlias = "erumpay-dev",
    [string]$PolicyName = "AWSLoadBalancerControllerIAMPolicy",
    [string]$RoleName = "AmazonEKSLoadBalancerControllerRole",
    [string]$ControllerVersion = "v2.14.1"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Checking AWS identity"
$identity = aws sts get-caller-identity | ConvertFrom-Json
$accountId = $identity.Account
$policyArn = "arn:aws:iam::$accountId:policy/$PolicyName"

Write-Host "==> Updating kubeconfig: $ClusterName ($Region)"
aws eks update-kubeconfig --region $Region --name $ClusterName --alias $ContextAlias
kubectl config use-context $ContextAlias
kubectl get nodes

Write-Host "==> Resolving VPC ID"
$vpcId = aws eks describe-cluster `
    --region $Region `
    --name $ClusterName `
    --query "cluster.resourcesVpcConfig.vpcId" `
    --output text
Write-Host "VPC ID: $vpcId"

Write-Host "==> Associating IAM OIDC provider"
eksctl utils associate-iam-oidc-provider `
    --region $Region `
    --cluster $ClusterName `
    --approve

Write-Host "==> Preparing IAM policy: $PolicyName"
$policyPath = Join-Path $env:TEMP "aws-load-balancer-controller-iam-policy.json"
$policyUrl = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/$ControllerVersion/docs/install/iam_policy.json"
Invoke-WebRequest -Uri $policyUrl -OutFile $policyPath

$policyExists = $true
try {
    aws iam get-policy --policy-arn $policyArn | Out-Null
} catch {
    $policyExists = $false
}

if ($policyExists) {
    Write-Host "IAM policy already exists: $policyArn"
} else {
    aws iam create-policy `
        --policy-name $PolicyName `
        --policy-document "file://$policyPath" | Out-Null
    Write-Host "Created IAM policy: $policyArn"
}

Write-Host "==> Creating or updating controller service account"
eksctl create iamserviceaccount `
    --cluster $ClusterName `
    --region $Region `
    --namespace kube-system `
    --name aws-load-balancer-controller `
    --role-name $RoleName `
    --attach-policy-arn $policyArn `
    --approve `
    --override-existing-serviceaccounts

Write-Host "==> Installing AWS Load Balancer Controller with Helm"
helm repo add eks https://aws.github.io/eks-charts --force-update
helm repo update eks

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller `
    --namespace kube-system `
    --set clusterName=$ClusterName `
    --set serviceAccount.create=false `
    --set serviceAccount.name=aws-load-balancer-controller `
    --set region=$Region `
    --set vpcId=$vpcId

Write-Host "==> Verifying controller rollout"
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
