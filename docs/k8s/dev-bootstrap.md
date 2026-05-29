# Dev environment bootstrap

This document describes the daily dev environment bootstrap flow after Terraform creates AWS resources.

## 1. Terraform apply

```powershell
cd C:\erumpay\erumpay-infra\terraform\envs\dev
terraform init
terraform plan
terraform apply
```

## 2. Configure kubeconfig

```powershell
cd C:\erumpay\erumpay-infra
.\scripts\k8s\update-kubeconfig.ps1
```

Verify:

```powershell
kubectl get nodes
```

## 3. Create namespaces

```powershell
kubectl create namespace platform-operations --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace pg --dry-run=client -o yaml | kubectl apply -f -
```

## 4. Install AWS Load Balancer Controller

```powershell
cd C:\erumpay\erumpay-infra
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\install-aws-load-balancer-controller.ps1
```

Verify:

```powershell
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get endpoints -n kube-system aws-load-balancer-webhook-service
```

If the webhook endpoint is `<none>`, make sure the controller ServiceAccount has the IAM role annotation.

```powershell
$AccountId = "512138915880"
$RoleArn = "arn:aws:iam::$AccountId:role/AmazonEKSLoadBalancerControllerRole"

kubectl create serviceaccount aws-load-balancer-controller -n kube-system
kubectl annotate serviceaccount aws-load-balancer-controller `
  -n kube-system `
  eks.amazonaws.com/role-arn=$RoleArn `
  --overwrite

kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=300s
kubectl get endpoints -n kube-system aws-load-balancer-webhook-service
```

## 5. Install Argo CD

```powershell
kubectl apply -n platform-operations `
  --server-side `
  --force-conflicts `
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Verify:

```powershell
kubectl get pods -n platform-operations
```

## 6. Create RDS secrets

Create the secret used by the DB init Job.

```powershell
kubectl delete secret erumpay-rds-secret -n platform-operations --ignore-not-found
kubectl create secret generic erumpay-rds-secret `
  -n platform-operations `
  --from-literal=DB_USERNAME=erumpay `
  --from-literal=DB_PASSWORD=<RDS_PASSWORD>
```

Create the secret used by pg-payment-service.

```powershell
kubectl delete secret pg-payment-service-secret -n pg --ignore-not-found
kubectl create secret generic pg-payment-service-secret `
  -n pg `
  --from-literal=DB_USERNAME=erumpay `
  --from-literal=DB_PASSWORD=<RDS_PASSWORD>
```

`<RDS_PASSWORD>` must match the RDS master password used by Terraform.

## 7. Run RDS schema init Job

RDS does not run `mysql/init` SQL files automatically. After Terraform creates RDS, run the DB init Job to create schemas and seed data.

```powershell
cd C:\erumpay\erumpay-infra
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\run-db-init.ps1
```

The script resolves the current RDS endpoint with AWS CLI, renders a temporary Job manifest from `k8s/jobs/db-init-job.yaml`, and waits for the Job to complete.

Manual fallback:

```powershell
kubectl delete job erumpay-db-init -n platform-operations --ignore-not-found
kubectl apply -f k8s\jobs\db-init-job.yaml
kubectl wait --for=condition=complete job/erumpay-db-init -n platform-operations --timeout=600s
kubectl logs -n platform-operations job/erumpay-db-init --tail=-1
```

When using the manual fallback, make sure `DB_HOST` in `k8s/jobs/db-init-job.yaml` matches the current RDS endpoint.

Notes:

```text
db-init/Dockerfile is not executed by Terraform.
db-init/Dockerfile is not part of pg-payment CI.
The actual schema creation happens when the Kubernetes Job runs.
The db-init image must already exist in ECR.
Rebuild and push the db-init image only when SQL files or db-init Dockerfile change.
```

## 8. Apply Argo CD Application

```powershell
kubectl apply -f argocd\applications\pg-payment-service-dev.yaml
kubectl annotate application pg-payment-service-dev `
  -n platform-operations `
  argocd.argoproj.io/refresh=hard `
  --overwrite
```

Verify:

```powershell
kubectl get application pg-payment-service-dev -n platform-operations
kubectl get pods -n pg
kubectl rollout status deployment/pg-payment-service -n pg
```

Expected:

```text
pg-payment-service-dev: Synced / Healthy
pg-payment-service pods: 1/1 Running
```
