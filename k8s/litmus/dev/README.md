# ErumPay Litmus Chaos Infrastructure

이 디렉터리는 dev EKS 클러스터용 Litmus Chaos Infrastructure 매니페스트를 보관한다.

> **⚠️ 이 폴더는 ArgoCD가 관리하지 않는다. 수동 배포 전용이다.**
>
> infra 매니페스트의 `INFRA_ID` / `ACCESS_KEY`는 ChaosCenter UI에서 Infra를 만들 때마다 새로 발급되므로
> GitOps로 관리하면 UI 재생성 → 로컬 수정 → push → sync 루프가 생긴다. 그래서 ArgoCD 관리 대상에서 제외했다.

## 배포 절차 (클러스터 신규 구축 시)

1. ChaosCenter 본체는 ArgoCD `litmus-dev` Application(Helm chart)이 자동 배포한다.
   단, MongoDB가 사용하는 StorageClass는 ArgoCD Application 적용 **전에** 수동 생성해야 한다:

   ```bash
   kubectl apply -f k8s/litmus/dev/mongodb-retain-storageclass.yaml
   ```

2. ChaosCenter UI 접속:

   ```bash
   kubectl port-forward svc/litmus-frontend-service -n platform-operations 9091:9091
   ```

3. UI에서 Environment 생성 → Enable Chaos Infrastructure
   (scope: Cluster, namespace: `platform-operations`, service account: `litmus`) → manifest YAML 다운로드

4. 다운로드한 YAML에서 `subscriber-config` ConfigMap의 `SERVER_ADDR`을 cluster-local 주소로 수정:

   ```text
   http://litmus-server-service.platform-operations.svc.cluster.local:9002/query
   ```

5. 수동 apply (git push / ArgoCD 불필요):

   ```bash
   kubectl apply -f <다운로드한-파일>.yml
   ```

6. UI Environments에서 infra 상태가 CONNECTED(초록)인지 확인.

## 주의

- `erumpay-dev-eks-infra-litmus-chaos-enable.yml`은 기록/백업용 원본이다. 배포 경로가 아니다.
- UI에서 Infra를 삭제하면 위 3~5단계를 다시 해야 하니 삭제하지 말 것.
- subscriber secret의 access key는 ChaosCenter가 발급한다. Infra를 재생성했으면 이 파일도 새 YAML로 교체해두면 좋다(백업 목적).
