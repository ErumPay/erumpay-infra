# LitmusChaos Dev 실행 가이드

이 문서는 dev 환경 배포 완료 후 LitmusChaos를 사용해 Chaos Experiment를 실행하는 절차를 정리한다.

기준 터미널은 Git Bash / MINGW64이다.

## 1. 전체 흐름

```text
1. dev 배포 상태 확인
2. LitmusChaos / ChaosCenter Pod, Service 확인
3. 9091 포트포워딩으로 ChaosCenter UI 접속
4. Environment 생성 또는 확인
5. Infrastructure 생성 또는 확인
6. ChaosCenter에서 Infrastructure manifest 다운로드
7. manifest의 SERVER_ADDR 확인 및 수정
8. manifest 적용
9. Infrastructure Connected 확인
10. Chaos Experiment 실행
```

## 2. 배포 상태 확인

```bash
cd /c/erum-pay/erumpay-infra

aws sts get-caller-identity
kubectl config current-context
kubectl get nodes
kubectl get application -n platform-operations
```

서비스 Pod 확인:

```bash
kubectl get pods -n gateway
kubectl get pods -n pay
kubectl get pods -n pg
kubectl get pods -n middleware
kubectl get pods -n platform-operations
```

정상 기준:

```text
Argo CD Application: Synced / Healthy
서비스 Pod: Running
Ingress: ADDRESS 생성
```

## 3. LitmusChaos Argo CD Application 적용

LitmusChaos는 Argo CD Application 2개로 관리한다.

```text
argocd/applications/litmus-dev.yaml
argocd/applications/litmus-chaos-infra-dev.yaml
```

각 Application의 역할:

```text
litmus-dev
- ChaosCenter를 Litmus Helm chart로 설치한다.

litmus-chaos-infra-dev
- ChaosCenter에서 생성한 Infrastructure manifest를 적용한다.
```

Application 적용:

```bash
cd /c/erum-pay/erumpay-infra

kubectl apply -f argocd/applications/litmus-dev.yaml
kubectl apply -f argocd/applications/litmus-chaos-infra-dev.yaml
```

상태 확인:

```bash
kubectl get application -n platform-operations litmus-dev litmus-chaos-infra-dev
```

필요 시 hard refresh:

```bash
kubectl annotate application litmus-dev \
  -n platform-operations \
  argocd.argoproj.io/refresh=hard \
  --overwrite

kubectl annotate application litmus-chaos-infra-dev \
  -n platform-operations \
  argocd.argoproj.io/refresh=hard \
  --overwrite

kubectl get application -n platform-operations litmus-dev litmus-chaos-infra-dev
```

## 4. LitmusChaos Pod / Service 확인

전체 확인:

```bash
kubectl get pods -n platform-operations
kubectl get svc -n platform-operations
```

Litmus 관련 Pod만 확인:

```bash
kubectl get pods -n platform-operations | grep -E "litmus|mongo|subscriber|event-tracker|chaos|workflow"
```

Litmus 관련 Service만 확인:

```bash
kubectl get svc -n platform-operations | grep -E "litmus|chaos|frontend|server|9091"
```

주요 ChaosCenter 구성요소:

```text
litmusportal-frontend
litmusportal-server
litmusportal-auth-server
mongo
```

주요 Infrastructure 구성요소:

```text
subscriber
event-tracker
chaos-operator
chaos-exporter
workflow-controller
```

Pod와 Service 개수는 Litmus chart 버전에 따라 달라질 수 있다. 숫자보다 관련 Pod가 `Running`인지, Argo CD Application이 `Synced / Healthy`인지 확인한다.

## 5. ChaosCenter UI 포트포워딩

포트포워딩 전에 `kubectl`이 EKS에 연결되는지 먼저 확인한다.

```bash
kubectl get nodes
```

아래처럼 EKS API 서버 DNS를 찾지 못하면 kubeconfig가 예전 클러스터 endpoint를 보고 있을 수 있다.

```text
Unable to connect to the server: dial tcp: lookup ...eks.amazonaws.com: no such host
```

이 경우 kubeconfig를 다시 생성한다.

```bash
aws sts get-caller-identity
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name erumpay-eks-cluster \
  --alias erumpay-dev

kubectl config use-context erumpay-dev
kubectl get nodes
```

프론트엔드 Service 이름 확인:

```bash
kubectl get svc -n platform-operations | grep -E "frontend|9091|litmus"
```

현재 Litmus Helm chart 3.26.0 기준 Service 이름:

```text
litmus-frontend-service
```

포트포워딩 실행:

```bash
kubectl port-forward -n platform-operations svc/litmus-frontend-service 9091:9091
```

여러 줄로 입력할 경우 Git Bash에서는 백틱(`)이 아니라 백슬래시(\)를 사용한다.

```bash
kubectl port-forward \
  -n platform-operations \
  svc/litmus-frontend-service \
  9091:9091
```

브라우저 접속:

```text
http://localhost:9091
```

기본 계정:

```text
ID: admin
PW: litmus
```

처음 로그인하면 기본 비밀번호 변경 화면으로 이동한다.

LitmusChaos 비밀번호 정책:

```text
8자 이상 16자 이하
숫자 1개 이상
소문자 1개 이상
대문자 1개 이상
특수문자 1개 이상
기존 비밀번호와 달라야 함
```

예시:

```text
Old Password: litmus
New Password: Litmus@123
Re-enter new password: Litmus@123
```

비밀번호 변경이 계속 실패하면 `litmus-auth-server` 로그를 확인한다.

```bash
kubectl logs -n platform-operations deployment/litmus-auth-server --tail=100
kubectl logs -n platform-operations deployment/litmus-server --tail=100
```

`litmus-dev`가 `Progressing`이면 MongoDB readiness도 같이 확인한다.

```bash
kubectl get pods -n platform-operations | grep -E "litmus-mongodb|litmus-auth|litmus-server|litmus-frontend"
kubectl logs -n platform-operations litmus-mongodb-1 --tail=100
kubectl describe pod -n platform-operations litmus-mongodb-1
```

`litmus-mongodb-1`만 `0/1 Running`이면 Argo CD에서 `litmus-dev`가 계속 `Progressing`으로 보일 수 있다.

## 6. Environment 생성

ChaosCenter UI에서 진행한다.

```text
1. http://localhost:9091 접속
2. admin / litmus 로그인
3. Environments 메뉴 이동
4. New Environment 또는 Create Environment 클릭
5. dev Environment 생성
```

권장 값:

```text
Environment name: dev
Description: ErumPay dev EKS
```

이미 dev Environment가 있으면 새로 만들지 않고 기존 항목을 사용한다.

## 7. Infrastructure 생성

ChaosCenter UI에서 진행한다.

```text
1. Environments에서 dev 선택
2. Chaos Infrastructures 메뉴 이동
3. New Infrastructure 클릭
4. Kubernetes 선택
5. 아래 값으로 Infrastructure 생성
```

권장 값:

```text
Infrastructure name: erumpay-dev-eks
Installation location / namespace: platform-operations
Service account: litmus
Scope: Cluster
```

생성이 완료되면 ChaosCenter가 Infrastructure manifest를 제공한다.

## 8. Infrastructure manifest 저장

Infrastructure manifest는 Infrastructure를 새로 만들 때마다 다시 생성된다.

새 manifest에는 보통 아래 값들이 새로 들어간다.

```text
INFRA_ID
ACCESS_KEY
SERVER_ADDR
```

`INFRA_ID`와 `ACCESS_KEY`는 ChaosCenter가 새 Infrastructure를 식별하고 인증하기 위한 값이므로 새로 받은 값을 유지해야 한다. 반면 `SERVER_ADDR`는 포트포워딩으로 접속한 주소를 따라 `localhost:9091`로 생성될 수 있으므로, 클러스터 내부 Service 주소로 바꿔야 한다.

임시 테스트만 하는 경우:

```bash
cd /c/erum-pay
kubectl apply -f ./local-litmus-chaos-enable.yml
```

레포 기준 권장 저장 위치:

```text
C:\erum-pay\erumpay-infra\k8s\litmus\dev\erumpay-dev-eks-infra-litmus-chaos-enable.yml
```

Git Bash 경로:

```text
/c/erum-pay/erumpay-infra/k8s/litmus/dev/erumpay-dev-eks-infra-litmus-chaos-enable.yml
```

`kustomization.yaml` 확인:

```bash
cat /c/erum-pay/erumpay-infra/k8s/litmus/dev/kustomization.yaml
```

기대 값:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - erumpay-dev-eks-infra-litmus-chaos-enable.yml
```

## 9. SERVER_ADDR 확인

`9091` 포트포워딩 주소는 브라우저에서 ChaosCenter UI에 접속하기 위한 주소다.

```text
http://localhost:9091
```

Infrastructure의 `subscriber` Pod는 클러스터 내부에서 ChaosCenter 서버에 접속한다. 따라서 manifest 안의 `SERVER_ADDR`가 `localhost:9091`이면 안 된다.

현재 값 확인:

```bash
grep -n "SERVER_ADDR" /c/erum-pay/erumpay-infra/k8s/litmus/dev/erumpay-dev-eks-infra-litmus-chaos-enable.yml
```

잘못된 예:

```yaml
SERVER_ADDR: http://localhost:9091/api/query
```

ChaosCenter 서버 Service 이름 확인:

```bash
kubectl get svc -n platform-operations | grep -E "server|litmus"
```

현재 Litmus Helm chart 3.26.0 기준 서버 Service 이름:

```text
litmus-server-service
```

일반적으로 사용할 내부 주소:

```text
http://litmus-server-service.platform-operations.svc.cluster.local:9002/query
```

Service port 확인:

```bash
kubectl get svc litmus-server-service -n platform-operations -o wide
kubectl describe svc litmus-server-service -n platform-operations
```

현재 설치가 9002/http 구성이면 `SERVER_ADDR`를 아래 값으로 수정한다.

```yaml
SERVER_ADDR: http://litmus-server-service.platform-operations.svc.cluster.local:9002/query
```

Git Bash에서 새로 받은 manifest의 `SERVER_ADDR`를 한 번에 바꾸려면:

```bash
MANIFEST=/c/erum-pay/erumpay-infra/k8s/litmus/dev/erumpay-dev-eks-infra-litmus-chaos-enable.yml

sed -i 's#^[[:space:]]*SERVER_ADDR: .*#  SERVER_ADDR: http://litmus-server-service.platform-operations.svc.cluster.local:9002/query#' "$MANIFEST"

grep -n "SERVER_ADDR" "$MANIFEST"
```

현재 설치가 9004/https 구성이면 아래 값을 사용한다.

```yaml
SERVER_ADDR: https://litmus-server-service.platform-operations.svc.cluster.local:9004/query
```

## 10. manifest 적용

Kustomize로 적용:

```bash
cd /c/erum-pay/erumpay-infra

kubectl apply -k k8s/litmus/dev
```

이미 잘못된 `SERVER_ADDR`로 적용된 경우 ConfigMap을 임시 patch하고 subscriber를 재시작한다.

9002/http 구성:

```bash
kubectl patch configmap subscriber-config \
  -n platform-operations \
  --type merge \
  -p '{"data":{"SERVER_ADDR":"http://litmus-server-service.platform-operations.svc.cluster.local:9002/query"}}'

kubectl rollout restart deployment/subscriber -n platform-operations
```

9004/https 구성:

```bash
kubectl patch configmap subscriber-config \
  -n platform-operations \
  --type merge \
  -p '{"data":{"SERVER_ADDR":"https://litmus-server-service.platform-operations.svc.cluster.local:9004/query"}}'

kubectl rollout restart deployment/subscriber -n platform-operations
```

ConfigMap만 patch하면 Argo CD sync 시 다시 원복될 수 있다. manifest 파일도 같은 값으로 수정한다.

## 11. Infrastructure 연결 확인

Infrastructure 관련 Pod 확인:

```bash
kubectl get pods -n platform-operations | grep -E "subscriber|event-tracker|chaos-operator|chaos-exporter|workflow-controller"
```

subscriber 로그 확인:

```bash
kubectl logs -n platform-operations deployment/subscriber --tail=100
```

event-tracker 로그 확인:

```bash
kubectl logs -n platform-operations deployment/event-tracker --tail=100
```

ChaosCenter UI에서 확인:

```text
Environments
-> dev
-> Chaos Infrastructures
-> erumpay-dev-eks
-> Connected 확인
```

Disconnected 상태일 때 확인할 항목:

```bash
kubectl get configmap -n platform-operations subscriber-config -o yaml
kubectl get secret -n platform-operations subscriber-secret -o yaml
kubectl describe pod -n platform-operations -l app=subscriber
```

주요 원인:

```text
SERVER_ADDR가 localhost로 되어 있음
Infrastructure를 삭제 후 재생성하여 access key가 변경됨
manifest namespace가 platform-operations가 아님
litmus-server-service가 아직 준비되지 않음
Argo CD가 subscriber-secret ACCESS_KEY를 초기 manifest 값으로 되돌림
```

subscriber 로그에 아래 에러가 나오면 access key가 꼬인 상태다.

```text
ERROR:  accessID MISMATCH
```

Litmus subscriber는 최초 등록 시 manifest의 초기 `ACCESS_KEY`로 서버에 확인 요청을 보내고, 서버가 새 `ACCESS_KEY`를 발급한다. subscriber는 새 키를 `subscriber-secret`에 저장하고 `subscriber-config`의 `IS_INFRA_CONFIRMED`를 `true`로 바꾼다.

따라서 Argo CD가 이 두 값을 Git의 초기 manifest 값으로 되돌리면 Infrastructure가 다시 `Inactive`가 된다. `litmus-chaos-infra-dev` Application에는 아래 필드가 ignoreDifferences로 들어 있어야 한다.

```yaml
ignoreDifferences:
  - kind: ConfigMap
    name: subscriber-config
    namespace: platform-operations
    jsonPointers:
      - /data/IS_INFRA_CONFIRMED
  - kind: Secret
    name: subscriber-secret
    namespace: platform-operations
    jsonPointers:
      - /data/ACCESS_KEY
```

이미 `accessID MISMATCH`가 발생한 경우 가장 빠른 복구 절차:

```text
1. ChaosCenter UI에서 Inactive Infrastructure 삭제
2. Kubernetes에서 기존 subscriber 리소스 삭제
3. ChaosCenter UI에서 Infrastructure 새로 생성
4. 새 manifest 다운로드
5. manifest를 k8s/litmus/dev/erumpay-dev-eks-infra-litmus-chaos-enable.yml에 저장
6. SERVER_ADDR를 내부 주소로 수정
7. kubectl apply -k /c/erum-pay/erumpay-infra/k8s/litmus/dev
8. subscriber 로그에서 confirmed 확인
```

기존 subscriber 리소스 삭제:

```bash
kubectl delete deployment subscriber event-tracker chaos-operator-ce chaos-exporter workflow-controller -n platform-operations --ignore-not-found
kubectl delete configmap subscriber-config workflow-controller-configmap -n platform-operations --ignore-not-found
kubectl delete secret subscriber-secret -n platform-operations --ignore-not-found
```

## 12. 첫 Chaos Experiment 실행

첫 실험은 영향도가 낮은 `pod-delete`를 권장한다.

추천 대상:

```text
api-gateway / gateway namespace
recommendation-service / pay namespace
notification-service / pay namespace
```

처음부터 피할 대상:

```text
RDS
Kafka
Redis
단일 replica 핵심 결제 서비스
stateful middleware
```

대상 Deployment 확인:

```bash
kubectl get deploy -A
kubectl get pods -n gateway
kubectl get pods -n pay
```

실험 중 Pod 변화 확인:

```bash
kubectl get pods -n gateway -w
```

Chaos 리소스 확인:

```bash
kubectl get chaosengine,chaosresult -A
kubectl get workflow -n platform-operations
```

실험 후 결과 확인:

```bash
kubectl get pods -n gateway
kubectl get chaosresult -A
```

정상 기준:

```text
Experiment run: Completed
Chaos result: Pass
삭제된 Pod 재생성
서비스 정상 복구
```

## 13. 매일 9시 배포 후 실행 명령어

아래 순서로 실행한다.

```bash
cd /c/erum-pay/erumpay-infra

aws sts get-caller-identity
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name erumpay-eks-cluster \
  --alias erumpay-dev
kubectl config use-context erumpay-dev
kubectl get nodes

kubectl get application -n platform-operations
kubectl get pods -n platform-operations
kubectl get svc -n platform-operations
kubectl get svc -n platform-operations | grep -E "frontend|server|9091|litmus"
```

ChaosCenter UI 포트포워딩:

```bash
kubectl port-forward -n platform-operations svc/litmus-frontend-service 9091:9091
```

브라우저 접속:

```text
http://localhost:9091
```

UI 확인 항목:

```text
1. dev Environment 존재 확인
2. erumpay-dev-eks Infrastructure Connected 확인
3. Disconnected면 subscriber 로그와 SERVER_ADDR 확인
4. 계획한 실험만 실행
5. 실험 결과 캡처 또는 로그 저장
6. 대상 Pod 복구 확인
```

## 14. GitOps 반영

Infrastructure manifest를 레포에 반영할 경우:

```bash
cd /c/erum-pay/erumpay-infra

git status
git add k8s/litmus/dev/erumpay-dev-eks-infra-litmus-chaos-enable.yml k8s/litmus/dev/kustomization.yaml
git commit -m "Add LitmusChaos dev infrastructure manifest"
git push origin develop
```

이후 Argo CD가 `litmus-chaos-infra-dev` Application을 통해 manifest를 적용한다.
