# Meetbowl Production Deployment Architecture

## 목적

이 문서는 운영 배포 1단계 결과로 확정한 런타임 구조를 정리한다.

대상은 `main` 브랜치 머지 시 자동 배포되는 운영 단일 환경(`prod`)이다.

---

## 확정 사항

- 배포 방식: Docker + Docker Compose
- 배포 트리거: GitHub `main` 머지 후 자동 배포
- 운영 환경: `prod` 단일 환경
- 이미지 저장소: AWS ECR
- 리버스 프록시: Nginx
- 업무 DB: AWS RDS MariaDB `11.8.8`
- DB migration: Flyway
- 운영 DB 가용성: 현재 RDS Multi-AZ 유지
- 초기 데이터: 운영 마스터 데이터 포함
- 최초 관리자 계정: 자동 생성

---

## 운영 런타임 구조

운영 EC2 한 대에는 아래 컨테이너를 올린다.

| Service | 배치 위치 | 역할 |
|---|---|---|
| nginx | EC2 container | 외부 진입점, reverse proxy, HTTPS 종료 |
| meetbowl-be | EC2 container | 기존 단일 배포 fallback 모드(`all`) |
| meetbowl-be-api | EC2 container | 사용자 요청 전용 API 모드 |
| meetbowl-be-worker | EC2 container | 스케줄러 / RabbitMQ consumer 전용 worker 모드 |
| meetbowl-ai | EC2 container | 회의록 생성, 임베딩, RAG, 실시간 피드백 |
| meetbowl-stt | EC2 container | LiveKit 오디오 수신, STT, transcript 이벤트 발행 |
| rabbitmq | EC2 container | 비동기 작업 큐 |
| redis | EC2 container | 토큰 상태, Redis Stream |
| livekit | EC2 container | 회의 media session, DataChannel |
| qdrant | EC2 container | AI 벡터 저장소 |

MariaDB는 EC2에 두지 않고 RDS를 사용한다.

---

## 네트워크 경계

외부에서 직접 접근 가능한 엔드포인트는 Nginx만 둔다.

- `443/tcp`: public
- `80/tcp`: 가능하면 HTTPS redirect 용도만 유지

외부 직접 노출 대상:

- `nginx`
- 필요 시 `livekit`의 RTC/TURN 관련 포트

외부 직접 비노출 대상:

- `meetbowl-be`
- `meetbowl-ai`
- `meetbowl-stt`
- `rabbitmq`
- `redis`
- `qdrant`

운영 보안그룹 기준:

- EC2 inbound
  - `80/tcp`, `443/tcp`
  - `7881/tcp`, `7882/udp`는 LiveKit 운영 방식 검토 후 개방
- RDS inbound
  - EC2 security group 에서만 `3306/tcp`

---

## 트래픽 흐름

### 사용자 요청

```text
Internet
  -> Nginx
  -> meetbowl-be-api
```

### 회의 입장 / 미디어 세션

```text
Frontend
  -> Nginx(/api) -> meetbowl-be-api
  -> LiveKit 직접 연결
  -> meetbowl-stt
```

### 비동기 회의록 생성

```text
meetbowl-be-worker
  -> RabbitMQ
  -> meetbowl-ai
  -> meetbowl-be-worker
```

### 실시간 피드백

```text
meetbowl-stt
  -> Redis Stream
  -> meetbowl-ai
  -> Redis Stream
  -> meetbowl-stt
  -> LiveKit DataChannel
```

---

## 운영 Compose 원칙

운영 compose 파일은 로컬 개발 compose와 분리한다.

예상 파일:

```text
meetbowl-infra/
  shared/compose.prod.yml
  be/compose.prod.yml
  be-api/compose.prod.yml
  be-worker/compose.prod.yml
  stt/compose.prod.yml
  nginx/
    prod.conf
  scripts/
    deploy-be.sh
    deploy-be-api.sh
    deploy-be-worker.sh
    deploy-be-split.sh
    deploy-stt.sh
```

운영 compose 원칙:

- `mariadb` 서비스는 제거하고 RDS endpoint를 사용한다.
- 각 애플리케이션은 ECR image tag를 사용한다.
- `depends_on`만으로 readiness를 보장하지 않고 healthcheck와 smoke test를 둔다.
- 비밀값은 파일 커밋 없이 런타임 주입한다.

---

## Secret 관리 원칙

운영 비밀값은 AWS Systems Manager Parameter Store를 기준으로 관리한다.

예시 경로:

```text
/meetbowl/prod/be/MEETBOWL_DB_URL
/meetbowl/prod/be/MEETBOWL_DB_USERNAME
/meetbowl/prod/be/MEETBOWL_DB_PASSWORD
/meetbowl/prod/be/MEETBOWL_JWT_SECRET
/meetbowl/prod/be/MEETBOWL_INTERNAL_TOKEN
/meetbowl/prod/shared/RABBITMQ_DEFAULT_PASS
/meetbowl/prod/shared/LIVEKIT_API_SECRET
```

EC2 IAM Role은 Parameter Store read 권한을 가져야 한다.

GitHub Actions에는 전체 애플리케이션 비밀값을 넣지 않고, AWS 배포 권한과 최소 서버 접근값만 둔다.

---

## 현재 코드베이스 기준 갭

운영 전환 전에 해결해야 하는 현재 갭은 아래와 같다.

1. `meetbowl-infra/docker-compose.yml`은 로컬 개발용이며 `mariadb`를 포함한다.
2. 운영 Parameter Store key 목록과 EC2 초기 세팅 문서는 서버별로 계속 확장해야 한다.

---

## 1단계 완료 기준

아래가 충족되면 운영 아키텍처 1단계가 끝난다.

- 운영 서비스 배치 위치가 문서로 고정됨
- 외부 노출 포트와 내부 전용 서비스 경계가 정리됨
- RDS 사용 원칙과 compose 분리 원칙이 정리됨
- secret 관리 기준이 정리됨
- 다음 단계의 구현 갭이 식별됨

---

## 전환 / 롤백 원칙

운영 전환은 기존 단일 배포(`meetbowl-be`, role=`all`)를 즉시 제거하지 않는 방향으로 진행한다.

기본 원칙은 아래와 같다.

1. 새 이미지 자체는 하나만 유지한다.
2. 실행 모드만 `MEETBOWL_APP_ROLE=all|api|worker`로 분리한다.
3. 분리 배포 검증이 끝나기 전까지는 `scripts/deploy-be.sh` 경로를 항상 유지한다.
4. 장애 시에는 `shared/compose.prod.yml + be/compose.prod.yml` 조합으로 즉시 복귀할 수 있어야 한다.

권장 전환 순서는 아래와 같다.

1. 기존 `deploy-be.sh`는 즉시 롤백 가능한 단일 모드(`all`) fallback 경로로 유지한다.
2. split 기본 경로는 `deploy-be-split.sh`를 사용한다.
3. `deploy-be-split.sh`는 먼저 `deploy-be-api.sh`로 API 컨테이너를 `api` 모드로 교체한다.
4. API health check가 통과하면 `deploy-be-worker.sh`로 worker 전용 인스턴스를 추가한다.
5. split 중 하나라도 실패하면 `deploy-be-split.sh`가 `deploy-be.sh`를 호출해 `all` 모드로 되돌린다.

권장 롤백 순서는 아래와 같다.

1. `deploy-be.sh`로 단일 모드(`all`) 컨테이너를 재기동한다.
2. Nginx `/healthz`, `/api/v1/health`가 회복됐는지 확인한다.
3. `deploy-be.sh`가 성공하면 남아 있던 `be-worker`는 정리한다.

즉, 분리 배포는 추가 경로이고, 단일 배포는 항상 살아있는 fallback 경로로 유지한다.

---

## 다음 단계

2단계는 `meetbowl-ai`, `meetbowl-stt`, `meetbowl-be` 운영 compose/env 계약과 EC2 배포 스크립트를 실제 값으로 검증하는 단계다.
