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
| meetbowl-be | EC2 container | 사용자 요청, 업무 상태, MariaDB 소유 |
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
  -> meetbowl-be
```

### 회의 입장 / 미디어 세션

```text
Frontend
  -> Nginx(/api) -> meetbowl-be
  -> LiveKit 직접 연결
  -> meetbowl-stt
```

### 비동기 회의록 생성

```text
meetbowl-be
  -> RabbitMQ
  -> meetbowl-ai
  -> meetbowl-be
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
  nginx/
    prod.conf
  scripts/
    deploy-be.sh
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
2. `meetbowl-ai`는 현재 Dockerfile이 없다.
3. `meetbowl-stt` 운영 Dockerfile/compose overlay가 아직 없다.
4. 운영 Parameter Store key 목록과 EC2 초기 세팅 문서가 아직 없다.
5. 서버별 배포 스크립트와 smoke test를 서비스별로 확장해야 한다.

---

## 1단계 완료 기준

아래가 충족되면 운영 아키텍처 1단계가 끝난다.

- 운영 서비스 배치 위치가 문서로 고정됨
- 외부 노출 포트와 내부 전용 서비스 경계가 정리됨
- RDS 사용 원칙과 compose 분리 원칙이 정리됨
- secret 관리 기준이 정리됨
- 다음 단계의 구현 갭이 식별됨

---

## 다음 단계

2단계는 `meetbowl-be` 운영 compose/env 계약과 EC2 배포 스크립트 정리다.
