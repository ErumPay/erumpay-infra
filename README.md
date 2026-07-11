# erumpay-infra

![AWS](https://img.shields.io/badge/AWS-EKS%20%C2%B7%20ECR%20%C2%B7%20RDS-FF9900?logo=amazonwebservices&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![ArgoCD](https://img.shields.io/badge/Argo%20CD-EF7B4D?logo=argo&logoColor=white)
![Jenkins](https://img.shields.io/badge/Jenkins-D24939?logo=jenkins&logoColor=white)

이룸페이(ErumPay)의 **인프라 단일 소스(Single Source of Truth) 레포지토리**입니다.

13개 마이크로서비스가 올라가는 AWS 인프라 프로비저닝(Terraform)부터 GitOps 배포(Helm + Argo CD), 시크릿 자동화(External Secrets), 데이터베이스 스키마, 관측성·카오스 엔지니어링까지 — 이룸페이를 띄우고 운영하는 데 필요한 모든 구성이 이 레포에 코드로 선언되어 있습니다.

---

## 목차

1. [아키텍처](#아키텍처)
2. [기술 스택](#기술-스택)
3. [레포지토리 구조](#레포지토리-구조)
4. [시작하기](#시작하기)
5. [Terraform — AWS 프로비저닝](#terraform--aws-프로비저닝)
6. [CI/CD — Jenkins + Argo CD GitOps](#cicd--jenkins--argo-cd-gitops)
7. [시크릿 관리 — External Secrets Operator](#시크릿-관리--external-secrets-operator)
8. [데이터베이스](#데이터베이스)
9. [관측성 · 카오스 엔지니어링](#관측성--카오스-엔지니어링)
10. [문서](#문서)
11. [Contributors](#contributors)

---

## 아키텍처

```
 개발자 push (서비스 레포)
      │
      ▼
 Jenkins ─── ① Gradle 빌드 · Docker 이미지 빌드
      │      ② AWS ECR 푸시 (커밋 해시 기반 태그)
      │      ③ 이 레포의 helm/values/dev/<service>.yaml 이미지 태그 커밋
      ▼
 erumpay-infra (Git = 단일 소스)
      │
      ▼
 Argo CD ─── Git 선언 상태를 EKS에 자동 동기화 (App of Apps, 22개 Application)
      │
      ▼
 AWS EKS ─┬─ 서비스 11종 (공용 Helm 차트)
          ├─ Kafka + Schema Registry · Redis
          ├─ Prometheus/Grafana · Zipkin · EFK
          ├─ External Secrets Operator ←── AWS Secrets Manager
          └─ LitmusChaos
```

- **CI/CD 책임 분리** — Jenkins는 빌드·푸시·values 태그 갱신까지만 수행하고, 클러스터 반영은 Argo CD가 Git 상태 기준으로 수행합니다. 커밋 해시 기반 동적 이미지 태깅으로 `:latest` 캐싱 문제를 원천 차단했습니다.
- **환경 분리** — `terraform/envs/<env>`, `helm/values/<env>`, `k8s/*/<env>` 구조로 환경별 구성을 분리합니다 (현재 dev).

## 기술 스택

| 분류 | 기술 |
|---|---|
| Cloud | AWS — EKS(v1.31) · ECR · RDS(MySQL) · VPC · Route53 · ALB · Secrets Manager |
| IaC | Terraform (모듈: vpc · eks · rds · ecr · security) |
| 배포 | Helm(공용 차트) · Argo CD(GitOps) |
| CI | Jenkins (서비스 레포별 Jenkinsfile) |
| 시크릿 | External Secrets Operator + AWS Secrets Manager |
| 미들웨어 | Apache Kafka + Schema Registry · Redis · MySQL |
| 관측성 | Prometheus · Grafana · Zipkin(분산 트레이싱) · EFK(Elasticsearch · Fluent Bit · Kibana) |
| 카오스 | LitmusChaos |
| DNS | ExternalDNS + Route53 |

## 레포지토리 구조

```
├── terraform/
│   ├── modules/                  # vpc · eks · rds · ecr · security 재사용 모듈
│   └── envs/dev/                 # dev 환경 루트 모듈 (main.tf · variables.tf · outputs.tf)
├── helm/
│   ├── charts/erumpay-service/   # 전 서비스 공용 차트 (Deployment/Service/Ingress/HPA/ConfigMap/Secret/SA)
│   └── values/dev/               # 서비스별 values 11종 — Jenkins가 이미지 태그를 갱신하는 지점
├── argocd/
│   └── applications/             # Argo CD Application 22종 (서비스 + 미들웨어 + 관측성 + 카오스)
├── k8s/
│   ├── external-secrets/dev/     # ClusterSecretStore + 서비스별 ExternalSecret
│   ├── external-dns/             # ExternalDNS (Route53 연동)
│   ├── monitoring/dev/           # chaos-exporter ServiceMonitor 등
│   ├── litmus/                   # LitmusChaos infra 매니페스트 (수동 배포)
│   ├── zipkin/ · schema-registry/
│   └── jobs/                     # DB 초기화 Job
├── mysql/
│   ├── init/                     # 서비스별 DB 스키마 10종 + 시드 데이터 (로컬/초기화용)
│   └── conf.d/                   # MySQL 설정
├── db-init/                      # 클러스터용 DB 초기화 이미지 (Dockerfile + 스크립트)
├── docker-compose.yml            # 로컬 통합 개발 환경 (MySQL·Kafka·Redis + 서비스 8종)
├── scripts/k8s/                  # 부트스트랩 스크립트 (kubeconfig · ALB Controller · DB init)
├── tools/card-benefit-seed/      # 카드 혜택 시드 데이터 생성 도구
└── docs/k8s/                     # 운영 가이드 문서 4종
```

## 시작하기

### 요구 사항

- Terraform, AWS CLI(자격 증명 구성), kubectl, Helm
- 로컬 개발: Docker + Docker Compose

### 로컬 통합 환경

```bash
# MySQL(스키마·시드 자동 초기화) + Kafka + Redis + 백엔드 서비스 8종
docker compose up -d
```

### 클러스터 부트스트랩 (dev)

```bash
# 1. AWS 인프라 프로비저닝
cd terraform/envs/dev && terraform init && terraform apply

# 2. kubeconfig 연결 및 ALB Controller 설치
./scripts/k8s/update-kubeconfig.ps1
./scripts/k8s/install-aws-load-balancer-controller.ps1

# 3. DB 초기화
./scripts/k8s/run-db-init.ps1

# 4. Argo CD 설치 후 Application 등록 → 이후 모든 배포는 GitOps로 자동화
kubectl apply -f argocd/applications/
```

상세 절차는 [Dev environment bootstrap](docs/k8s/dev-bootstrap.md) 문서를 참고하세요.

## Terraform — AWS 프로비저닝

| 모듈 | 내용 |
|---|---|
| `vpc` | VPC · IGW · Public/Private Subnet · NAT Gateway — 수동 생성돼 있던 기존 리소스 import 포함 |
| `eks` | EKS 클러스터(v1.31) · 용도별 노드그룹 4종(pay / pg / middleware / platform-operations) · ALB Controller IRSA |
| `rds` | RDS MySQL 인스턴스 |
| `ecr` | ECR 리포지토리 — 수동 생성돼 있던 14개 리포지토리를 import해 IaC로 일원화 |
| `security` | EKS 클러스터/노드/RDS Security Group |

서비스가 늘어날 때 노드그룹 증설, EKS 버전 업그레이드(1.29 → 1.31) 등 인프라 변경 이력이 전부 코드 리뷰를 거친 커밋으로 남아 있습니다.

## CI/CD — Jenkins + Argo CD GitOps

1. **CI (Jenkins)** — 각 서비스 레포의 `Jenkinsfile`이 빌드 → 커밋 해시 태그로 ECR 푸시 → 이 레포 `helm/values/dev/<service>.yaml`의 이미지 태그를 자동 커밋 (`erumpay-jenkins` 봇 커밋)
2. **CD (Argo CD)** — `argocd/applications/`의 22개 Application이 Git 상태를 감시하며 EKS에 자동 동기화. 서비스 11종뿐 아니라 Kafka·Redis·Zipkin·EFK·Prometheus/Grafana·Schema Registry·ExternalDNS까지 전부 선언적으로 관리
3. **공용 Helm 차트** — 서비스 11종이 `erumpay-service` 차트 하나를 공유하고 values만 분리. probe·리소스·HPA·Ingress·ServiceAccount가 표준화되어 새 서비스 추가 시 values 파일 하나로 배포 가능

> **예외 — LitmusChaos infra**: ChaosCenter가 Infra 생성 시마다 `INFRA_ID`/`ACCESS_KEY`를 새로 발급하는 stateful 컴포넌트라 선언적 GitOps 모델과 충돌합니다. ChaosCenter 본체만 Argo CD로 관리하고 infra(subscriber)는 `k8s/litmus/`에서 수동 배포하도록 분리했습니다.

## 시크릿 관리 — External Secrets Operator

시크릿 원문은 Git에 커밋하지 않습니다.

- **AWS Secrets Manager**에 시크릿 저장 → **External Secrets Operator(ESO)** 가 `ClusterSecretStore` + 서비스별 `ExternalSecret`(11종)을 통해 K8s Secret으로 자동 동기화
- ESO 전용 IAM Role/Policy도 Terraform으로 관리

## 데이터베이스

`mysql/init/`에 서비스별 스키마와 시드 데이터가 번호 순서로 정리되어 있습니다.

- **스키마 10종** — auth · card · payment · recommend · notification · pg-auth · pg-billing · pg-payment · pg-merchant · simulator (Database per Service)
- **시드 데이터** — 카드 상품(card-gorilla) · MCC 매핑 · 가맹점 키워드 · PG 가맹점
- 로컬은 docker-compose가 컨테이너 기동 시 자동 실행, 클러스터는 `db-init/` 이미지 + `k8s/jobs/db-init-job.yaml`로 초기화

## 관측성 · 카오스 엔지니어링

- **Prometheus + Grafana** — RED 메트릭 대시보드, chaos-exporter ServiceMonitor로 카오스 실험 지표 연동
- **Zipkin** — 결제 → 추천 → 알림 전체 흐름 분산 트레이싱
- **EFK** — Elasticsearch · Fluent Bit · Kibana 중앙 로그 수집
- **LitmusChaos** — 파드 삭제 · 메모리 부하 · 네트워크 지연 · 네트워크 로스 4종 실험으로 장애 회복력 검증 ([가이드](docs/k8s/litmus-chaos-guide.md))

## 문서

- [Dev environment bootstrap](docs/k8s/dev-bootstrap.md)
- [kubectl connection](docs/k8s/kubectl-connection.md)
- [Ingress controller](docs/k8s/ingress-controller.md)
- [LitmusChaos dev guide](docs/k8s/litmus-chaos-guide.md)
