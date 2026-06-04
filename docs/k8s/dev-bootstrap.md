# Dev Environment Bootstrap

매일 9시에 Terraform으로 dev 리소스를 생성한 뒤, EKS 위에 공통 구성과 서비스 배포 준비를 진행하는 순서다.

## 0. 최초 1회 준비

AWS Secrets Manager의 `erumpay/dev/all` 보안 암호는 매일 생성하지 않는다. 최초 1회 생성하고, 값이 바뀔 때만 AWS 콘솔 또는 AWS CLI에서 수정한다.

`erumpay/dev/all`에 필요한 key:

```text
DB_USERNAME
DB_PASSWORD
JWT_SECRET
AES_SECRET_KEY
PHONE_HASH_SALT
AUTH_KAKAO_CLIENT_SECRET
PG_AUTH_KAKAO_CLIENT_SECRET
PG_AUTH_INTERNAL_API_KEY
CARD_BILLING_KEY_AES_KEY
PG_PAYMENT_RECONCILIATION_AUTHORIZATION
```

확인:

```powershell
aws secretsmanager describe-secret `
  --region ap-northeast-2 `
  --secret-id erumpay/dev/all
```

## 1. Terraform 실행

```powershell
cd C:\erumpay\erumpay-infra\terraform\envs\dev

terraform init
terraform plan
terraform apply
```

Terraform이 생성하는 주요 항목:

```text
VPC / Subnet / NAT
EKS / Node Group
RDS
ECR repositories
RDS 보안그룹 EKS 접근 규칙
EKS OIDC Provider
External Secrets Operator용 IAM Role / Policy
```

OIDC Provider가 이미 존재한다는 오류가 나면 삭제하지 말고 Terraform state로 import한다.

```powershell
$AccountId = aws sts get-caller-identity --query Account --output text
$OidcIssuer = aws eks describe-cluster `
  --region ap-northeast-2 `
  --name erumpay-eks-cluster `
  --query "cluster.identity.oidc.issuer" `
  --output text

$OidcHostPath = $OidcIssuer -replace "^https://", ""

terraform import aws_iam_openid_connect_provider.eks "arn:aws:iam::$AccountId:oidc-provider/$OidcHostPath"

terraform plan
terraform apply
```

## 2. kubeconfig 설정

```powershell
cd C:\erumpay\erumpay-infra
.\scripts\k8s\update-kubeconfig.ps1
```

확인:

```powershell
kubectl config use-context erumpay-dev
kubectl get nodes
```

## 3. namespace 생성

```powershell
kubectl create namespace platform-operations --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gateway --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace pay --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace pg --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace middleware --dry-run=client -o yaml | kubectl apply -f -
```

확인:

```powershell
kubectl get ns
```

## 4. AWS Load Balancer Controller 설치

```powershell
cd C:\erumpay\erumpay-infra
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\install-aws-load-balancer-controller.ps1
```

확인:

```powershell
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get endpoints -n kube-system aws-load-balancer-webhook-service
```

정상 상태:

```text
aws-load-balancer-controller READY 1/1 또는 2/2
aws-load-balancer-webhook-service endpoint가 <none>이 아니어야 함
```

ServiceAccount 문제로 controller pod가 생성되지 않으면 아래를 실행한다.

```powershell
$AccountId = aws sts get-caller-identity --query Account --output text
$RoleArn = "arn:aws:iam::$AccountId:role/AmazonEKSLoadBalancerControllerRole"

kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | kubectl apply -f -

kubectl annotate serviceaccount aws-load-balancer-controller `
  -n kube-system `
  eks.amazonaws.com/role-arn=$RoleArn `
  --overwrite

kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=300s
kubectl get endpoints -n kube-system aws-load-balancer-webhook-service
```

## 5. Argo CD 설치

```powershell
kubectl apply -n platform-operations `
  --server-side `
  --force-conflicts `
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Argo CD Application Controller가 전체 namespace를 조회할 수 있도록 권한을 부여한다.

```powershell
kubectl create clusterrolebinding argocd-application-controller-cluster-admin `
  --clusterrole=cluster-admin `
  --serviceaccount=platform-operations:argocd-application-controller `
  --dry-run=client -o yaml | kubectl apply -f -
```

확인:

```powershell
kubectl get pods -n platform-operations
kubectl auth can-i list namespaces --as=system:serviceaccount:platform-operations:argocd-application-controller
```

## 6. External Secrets Operator 설치

Terraform이 만든 ESO IAM Role ARN을 가져온다.

```powershell
cd C:\erumpay\erumpay-infra\terraform\envs\dev
$EsoRoleArn = terraform output -raw external_secrets_role_arn
```

ESO를 Helm으로 설치한다. 이때 ServiceAccount에 IAM Role annotation을 함께 붙인다.

```powershell
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets `
  -n platform-operations `
  --create-namespace `
  --set installCRDs=true `
  --set serviceAccount.create=true `
  --set serviceAccount.name=external-secrets `
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$EsoRoleArn"
```

확인:

```powershell
kubectl rollout status deployment/external-secrets -n platform-operations --timeout=300s
kubectl get pods -n platform-operations | Select-String external-secrets
kubectl get sa external-secrets -n platform-operations -o yaml
```

ServiceAccount에 아래 annotation이 있어야 한다.

```text
eks.amazonaws.com/role-arn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/erumpay-external-secrets-role
```

## 7. ExternalSecret 적용

수동으로 `kubectl create secret`을 실행하지 않는다. ExternalSecret이 AWS Secrets Manager의 `erumpay/dev/all`을 읽어서 Kubernetes Secret을 자동 생성한다.

```powershell
cd C:\erumpay\erumpay-infra

kubectl apply -f k8s\external-secrets\dev\cluster-secret-store.yaml
kubectl apply -f k8s\external-secrets\dev
```

확인:

```powershell
kubectl get clustersecretstore
kubectl get externalsecret -A
kubectl get secret -n gateway
kubectl get secret -n pay
kubectl get secret -n pg
kubectl get secret -n platform-operations erumpay-rds-secret
```

정상 상태:

```text
ClusterSecretStore: Ready
ExternalSecret: SecretSynced 또는 Ready
각 namespace에 <service>-secret 생성
platform-operations에 erumpay-rds-secret 생성
```

## 8. db-init 이미지 push

Terraform은 ECR repository를 만들지만 Docker image를 push하지 않는다. ECR repository가 새로 생성된 날에는 `db-init` 이미지를 push해야 한다.

```powershell
cd C:\erumpay\erumpay-infra

aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 512138915880.dkr.ecr.ap-northeast-2.amazonaws.com

docker build `
  -t 512138915880.dkr.ecr.ap-northeast-2.amazonaws.com/erumpay/db-init:latest `
  -f db-init/Dockerfile .

docker push 512138915880.dkr.ecr.ap-northeast-2.amazonaws.com/erumpay/db-init:latest
```

## 9. RDS schema init Job 실행

RDS는 `mysql/init` SQL 파일을 자동 실행하지 않는다. RDS 생성 후 DB init Job을 실행해서 schema와 seed 데이터를 생성한다.

```powershell
cd C:\erumpay\erumpay-infra
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\run-db-init.ps1
```

확인:

```powershell
kubectl get job -n platform-operations erumpay-db-init
kubectl logs -n platform-operations job/erumpay-db-init --tail=-1
```

수동 fallback:

```powershell
kubectl delete job erumpay-db-init -n platform-operations --ignore-not-found
kubectl apply -f k8s\jobs\db-init-job.yaml
kubectl wait --for=condition=complete job/erumpay-db-init -n platform-operations --timeout=600s
kubectl logs -n platform-operations job/erumpay-db-init --tail=-1
```

주의:

```text
db-init/Dockerfile은 Terraform에서 실행되지 않는다.
db-init은 서비스 CI에 넣지 않는다.
실제 schema 생성은 Kubernetes Job이 실행될 때 일어난다.
```

## 10. Argo CD Application 적용

모든 서비스의 Argo CD Application을 적용한다.

```powershell
cd C:\erumpay\erumpay-infra
kubectl apply -f argocd\applications
```

강제 refresh가 필요하면:

```powershell
kubectl get application -n platform-operations -o name | ForEach-Object {
  kubectl annotate $_ `
    -n platform-operations `
    argocd.argoproj.io/refresh=hard `
    --overwrite
}
```

확인:

```powershell
kubectl get application -n platform-operations
kubectl get pods -n gateway
kubectl get pods -n pay
kubectl get pods -n pg
```

## 11. 서비스 이미지 push 확인

Terraform은 서비스 이미지를 ECR에 push하지 않는다. 서비스별 이미지는 Jenkins CI가 push한다.

ECR repository가 새로 생성되어 비어 있으면 Argo CD가 배포해도 pod가 `ImagePullBackOff`가 될 수 있다. 이 경우 해당 서비스의 Jenkins main 빌드를 먼저 실행해서 이미지를 ECR에 push한다.

```text
service repo main build
-> Jenkins Gradle build
-> Docker build
-> ECR push
-> infra repo develop image tag update
-> Argo CD sync
```

최종 확인:

```powershell
kubectl get pods -A
kubectl get ingress -A
kubectl get application -n platform-operations
```
