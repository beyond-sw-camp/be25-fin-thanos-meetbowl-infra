# Meetbowl BE Production Deploy Checklist

## 목적

이 문서는 `meetbowl-be` 운영 배포에 필요한 실제 등록값과 서버 준비 항목만 정리한다.

대상 범위는 아래로 한정한다.

- `meetbowl-be`
- `shared/compose.prod.yml`
- `shared/compose.api.prod.yml`
- `be/compose.prod.yml`
- `be-api/compose.prod.yml`
- `be-worker/compose.prod.yml`
- `scripts/deploy-be.sh`
- `scripts/deploy-be-api.sh`
- `scripts/deploy-be-worker.sh`
- `scripts/deploy-be-split.sh`

`meetbowl-ai`, `meetbowl-stt`는 같은 패턴을 재사용하되 이 문서 범위에는 포함하지 않는다.

---

## 배포 구조

기본 단일 배포는 아래 순서로 진행된다.

1. GitHub Actions가 `meetbowl-be` 이미지를 ECR에 push한다.
2. GitHub Actions가 EC2에 SSH 접속한다.
3. EC2의 `meetbowl-infra/scripts/deploy-be.sh`가 SSM Parameter Store 값을 읽는다.
4. `shared/compose.prod.yml + be/compose.prod.yml` 조합으로 `docker compose up -d`를 실행한다.
5. Nginx `/healthz` smoke test가 통과하면 배포 완료로 본다.

분리 배포를 사용할 때는 아래 조합을 추가로 사용한다.

```text
shared/compose.api.prod.yml + be-api/compose.prod.yml
shared/compose.prod.yml + be-worker/compose.prod.yml
```

권장 전환 순서는 아래와 같다.

1. 기본 자동 배포 경로는 API ASG + Worker EC2 분리 경로를 사용한다.
2. GitHub Actions가 `/meetbowl/prod/be-api/MEETBOWL_BE_IMAGE_TAG`를 현재 이미지 태그로 갱신한다.
3. GitHub Actions가 API ASG의 InService 인스턴스들에 SSM으로 `deploy-be-api.sh`를 실행한다.
4. API `/healthz`, `/api/v1/health`가 통과하면 Worker EC2에 `deploy-be-worker.sh`를 실행한다.
5. scheduler / RabbitMQ consumer / 검색 인덱스 초기화가 worker에서 정상 동작하는지 확인한다.
6. split 경로 장애 시에는 fallback EC2의 `deploy-be.sh` 경로로 수동 복귀한다.

권장 롤백 순서는 아래와 같다.

1. fallback EC2에서 `deploy-be.sh`로 단일 모드(`all`)를 다시 기동한다.
2. `/healthz`, `/api/v1/health`, 로그인/회의 입장 핵심 흐름을 확인한다.
3. ALB 또는 DNS를 fallback 경로로 전환한다.

---

## SSM Prefix

운영 SSM Parameter Store는 아래 prefix를 사용한다.

```text
/meetbowl/prod/shared
/meetbowl/prod/be
/meetbowl/prod/be-api
/meetbowl/prod/be-worker
```

`deploy-be.sh`는 위 두 prefix를 읽어 `.runtime/shared.env`, `.runtime/be.env`를 만든 뒤 shell 환경변수로 로드한다.
`deploy-be-api.sh`와 `deploy-be-worker.sh`는 `shared -> be -> 역할별 prefix` 순서로 로드한다.
즉 공통 앱 설정은 `/meetbowl/prod/be`를 기준으로 두고, 역할별 prefix는 override가 필요한 값만 두면 된다.
단, API ASG는 `shared/compose.api.prod.yml`을 사용하므로 `NGINX_CERTS_DIR`와 HTTPS 포트 검사가 필요하지 않다.

## 실행 역할

`meetbowl-be` 이미지는 동일하지만 `MEETBOWL_APP_ROLE`로 실행 모드를 나눈다.

```text
all: 기존 단일 배포 fallback
api: HTTP API 전용
worker: scheduler / RabbitMQ listener 전용
```

---

## 필수 Shared 파라미터

아래 값은 `deploy-be.sh`가 누락 시 즉시 실패 처리한다.

| SSM Key | 예시 값 | 용도 |
|---|---|---|
| `/meetbowl/prod/shared/NGINX_CERTS_DIR` | `/opt/meetbowl/certs` | Nginx 인증서 마운트 경로 |
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_USER` | `meetbowl` | RabbitMQ 기본 계정 |
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_PASS` | `********` | RabbitMQ 비밀번호 |
| `/meetbowl/prod/shared/LIVEKIT_API_KEY` | `prod-livekit-key` | BE token 발급용 key |
| `/meetbowl/prod/shared/LIVEKIT_API_SECRET` | `********` | LiveKit secret |
| `/meetbowl/prod/shared/LIVEKIT_NODE_IP` | `x.x.x.x` | LiveKit advertise IP |

아래 값은 기본값이 있으나 운영에서는 명시 등록을 권장한다.

| SSM Key | 기본값 | 비고 |
|---|---|---|
| `/meetbowl/prod/shared/REDIS_PORT` | `6379` | 로컬 바인드 포트 |
| `/meetbowl/prod/shared/REDIS_BIND_ADDRESS` | `127.0.0.1` | 외부 직접 비노출 권장 |
| `/meetbowl/prod/shared/RABBITMQ_AMQP_PORT` | `5672` | |
| `/meetbowl/prod/shared/RABBITMQ_AMQP_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/RABBITMQ_MANAGEMENT_PORT` | `15672` | |
| `/meetbowl/prod/shared/RABBITMQ_MANAGEMENT_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_VHOST` | `/` | |
| `/meetbowl/prod/shared/LIVEKIT_HTTP_PORT` | `7880` | |
| `/meetbowl/prod/shared/LIVEKIT_HTTP_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/LIVEKIT_RTC_TCP_PORT` | `7881` | 외부 보안그룹 확인 |
| `/meetbowl/prod/shared/LIVEKIT_RTC_UDP_PORT` | `7882` | 외부 보안그룹 확인 |
| `/meetbowl/prod/shared/QDRANT_HTTP_PORT` | `6333` | |
| `/meetbowl/prod/shared/QDRANT_HTTP_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/QDRANT_GRPC_PORT` | `6334` | |
| `/meetbowl/prod/shared/QDRANT_GRPC_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/ELASTICSEARCH_HTTP_PORT` | `9200` | |
| `/meetbowl/prod/shared/ELASTICSEARCH_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/ELASTICSEARCH_JAVA_OPTS` | `-Xms512m -Xmx512m` | |
| `/meetbowl/prod/shared/NGINX_HTTP_PORT` | `80` | |
| `/meetbowl/prod/shared/NGINX_HTTPS_PORT` | `443` | smoke test 대상 |

---

## 필수 BE 파라미터

아래 값은 `deploy-be.sh`가 누락 시 즉시 실패 처리한다.

| SSM Key | 예시 값 | 용도 |
|---|---|---|
| `/meetbowl/prod/be/MEETBOWL_DB_URL` | `jdbc:mariadb://...` | RDS 연결 URL |
| `/meetbowl/prod/be/MEETBOWL_DB_USERNAME` | `meetbowl` | DB 계정 |
| `/meetbowl/prod/be/MEETBOWL_DB_PASSWORD` | `********` | DB 비밀번호 |
| `/meetbowl/prod/be/MEETBOWL_JWT_SECRET` | `********` | JWT secret |
| `/meetbowl/prod/be/MEETBOWL_INTERNAL_TOKEN` | `********` | 서버 간 내부 토큰 |
| `/meetbowl/prod/be/MEETBOWL_CORS_ALLOWED_ORIGIN_PATTERNS` | `https://app.meetbowl.com,https://*.vercel.app` | 브라우저 CORS 허용 origin 패턴 |
| `/meetbowl/prod/be/MEETBOWL_LIVEKIT_URL` | `https://app.meetbowl.com/livekit` | 프론트 브라우저가 실제로 접속할 LiveKit 공개 URL |
| `/meetbowl/prod/be/MEETBOWL_STT_BASE_URL` | `http://meetbowl-stt:3000/api/v1` | STT 내부 호출 주소 |
| `/meetbowl/prod/be/MEETBOWL_AI_BASE_URL` | `http://meetbowl-ai:8000` | AI 내부 호출 주소 |
| `/meetbowl/prod/be/S3_BUCKET` | `meetbowl-prod-files` | 파일 저장 버킷 |

아래 값은 기본값이 있으나 운영에서는 명시 등록을 권장한다.

| SSM Key | 기본값 | 비고 |
|---|---|---|
| `/meetbowl/prod/be/MEETBOWL_BE_JAVA_OPTS` | `-Xms512m -Xmx1024m` | |
| `/meetbowl/prod/be/MEETBOWL_REDIS_HOST` | `redis` | shared network service name |
| `/meetbowl/prod/be/MEETBOWL_REDIS_PORT` | `6379` | |
| `/meetbowl/prod/be/MEETBOWL_RABBITMQ_HOST` | `rabbitmq` | |
| `/meetbowl/prod/be/MEETBOWL_RABBITMQ_PORT` | `5672` | |
| `/meetbowl/prod/be/MEETBOWL_RABBITMQ_USERNAME` | shared 계정 사용 | 운영에서는 명시 등록 권장 |
| `/meetbowl/prod/be/MEETBOWL_RABBITMQ_PASSWORD` | shared 계정 사용 | 운영에서는 명시 등록 권장 |
| `/meetbowl/prod/be/MEETBOWL_RABBITMQ_VHOST` | `/` | |
| `/meetbowl/prod/be/MEETBOWL_RABBITMQ_EXCHANGE` | `meetbowl.topic` | |
| `/meetbowl/prod/be/MEETBOWL_RABBITMQ_MINUTES_GENERATED_QUEUE` | `api.minutes.generated` | |
| `/meetbowl/prod/be-worker/MEETBOWL_BE_WORKER_JAVA_TOOL_OPTIONS` | `-Djava.net.preferIPv4Stack=true` | Amazon MQ DNS가 IPv6로만 resolve될 때 worker JVM의 IPv4 우선 사용 강제 |
| `/meetbowl/prod/be/MEETBOWL_LIVEKIT_TOKEN_EXPIRATION_SECONDS` | `3600` | |
| `/meetbowl/prod/be/MEETBOWL_STT_INTERNAL_TOKEN` | `MEETBOWL_INTERNAL_TOKEN` 재사용 가능 | |
| `/meetbowl/prod/be/MEETBOWL_ELASTICSEARCH_URL` | `http://elasticsearch:9200` | |
| `/meetbowl/prod/be/MEETBOWL_USER_SEARCH_INDEX` | `meetbowl-users` | |
| `/meetbowl/prod/be/MEETBOWL_ELASTICSEARCH_AUTO_CREATE_INDEX` | `false` | |
| `/meetbowl/prod/be/MEETBOWL_ELASTICSEARCH_REINDEX_BATCH_SIZE` | `200` | |
| `/meetbowl/prod/be/AWS_REGION` | `ap-northeast-2` | compose env 전달용 |
| `/meetbowl/prod/be/S3_ENDPOINT` | 빈 값 | AWS S3면 비워둘 수 있음 |
| `/meetbowl/prod/be/AWS_ACCESS_KEY_ID` | 빈 값 | EC2 IAM Role 사용 시 불필요 |
| `/meetbowl/prod/be/AWS_SECRET_ACCESS_KEY` | 빈 값 | EC2 IAM Role 사용 시 불필요 |

### API 전용 override 파라미터

`deploy-be-api.sh`는 `/meetbowl/prod/be-api` prefix에서 API 전용 값을 읽는다.

| SSM Key | 예시 값 | 용도 |
|---|---|---|
| `/meetbowl/prod/be-api/MEETBOWL_APP_ROLE` | `api` | API 전용 실행 역할 |
| `/meetbowl/prod/be-api/MEETBOWL_BE_IMAGE_TAG` | `git-sha` | API ASG 인스턴스가 부팅 시 사용할 현재 이미지 태그 |

API 전용으로 CORS나 Java 옵션을 다르게 가져가고 싶을 때만 `/meetbowl/prod/be-api`에 추가 override를 둔다.
그렇지 않으면 나머지 값은 모두 `/meetbowl/prod/be`만 사용하면 된다.
ASG 새 인스턴스도 같은 태그를 사용해야 하므로 launch template user data 또는 부팅 훅에서 `deploy-be-api.sh`를 실행해 이 값을 읽도록 구성해야 한다.

### Worker 전용 override 파라미터

`deploy-be-worker.sh`는 `/meetbowl/prod/be-worker` prefix에서 worker 전용 값을 읽는다.

| SSM Key | 예시 값 | 용도 |
|---|---|---|
| `/meetbowl/prod/be-worker/MEETBOWL_APP_ROLE` | `worker` | worker 전용 실행 역할 |

worker는 브라우저 트래픽을 직접 받지 않으므로 CORS 값을 override할 필요가 없다.
별도 JVM 메모리나 포트를 줄 때만 `/meetbowl/prod/be-worker`에 추가 override를 둔다.

---

## GitHub Secrets

`meetbowl-be` GitHub Actions는 아래 secret을 요구한다.

| Secret | 용도 |
|---|---|
| `AWS_GITHUB_ACTIONS_ROLE_ARN` | GitHub OIDC로 ECR push 및 배포 권한 획득 |
| `MEETBOWL_API_BLUE_ASG_NAME` | 현재 운영 API blue Auto Scaling Group 이름 |
| `MEETBOWL_API_BLUE_DEPLOY_PATH` | API blue EC2들의 `meetbowl-infra` 루트 경로 |
| `MEETBOWL_WORKER_EC2_HOST` | Worker EC2 접속 호스트 |
| `MEETBOWL_WORKER_EC2_USER` | Worker SSH 사용자 |
| `MEETBOWL_WORKER_EC2_SSH_KEY` | Worker private key |
| `MEETBOWL_WORKER_DEPLOY_PATH` | Worker EC2의 `meetbowl-infra` 루트 경로 |
| `MEETBOWL_FALLBACK_EC2_HOST` | fallback EC2 접속 호스트 |
| `MEETBOWL_FALLBACK_EC2_USER` | fallback SSH 사용자 |
| `MEETBOWL_FALLBACK_EC2_SSH_KEY` | fallback private key |
| `MEETBOWL_FALLBACK_DEPLOY_PATH` | fallback EC2의 `meetbowl-infra` 루트 경로 |

각 `*_DEPLOY_PATH`는 반드시 아래처럼 infra 레포 루트여야 한다.

```text
/opt/meetbowl/meetbowl-infra
```

---

## EC2 사전 준비

아래는 `meetbowl-be` 첫 배포 전에 완료되어야 한다.

1. API ASG, Worker EC2, fallback EC2에 `meetbowl-infra`가 clone 되어 있어야 한다.
2. `docker`, `docker compose`, `aws cli`, `curl`이 설치되어 있어야 한다.
3. API ASG instance profile 또는 attached role에는 아래 권한이 있어야 한다.

```text
ssm:GetParametersByPath
ssm:GetParameters
kms:Decrypt
ecr:GetAuthorizationToken
ecr:BatchGetImage
ecr:GetDownloadUrlForLayer
sts:GetCallerIdentity
```

4. API EC2는 SSM Agent와 `AmazonSSMManagedInstanceCore`에 준하는 권한이 있어야 한다.
5. API ASG launch template user data 또는 부팅 훅은 `deploy-be-api.sh`를 실행할 수 있어야 한다.

6. fallback EC2의 `NGINX_CERTS_DIR` 경로에 아래 파일이 있어야 한다.

```text
fullchain.pem
privkey.pem
```

7. RDS security group inbound는 EC2 security group에서만 `3306/tcp` 허용 상태여야 한다.

---

## 첫 배포 전 수동 점검

GitHub Actions 자동 배포 전에 EC2에서 아래를 먼저 확인하는 편이 안전하다.

1. `aws ssm get-parameters-by-path --path /meetbowl/prod/shared --with-decryption`
2. `aws ssm get-parameters-by-path --path /meetbowl/prod/be --with-decryption`
3. API EC2 한 대에서 `bash scripts/deploy-be-api.sh` 수동 실행
4. Worker EC2에서 `bash scripts/deploy-be-worker.sh` 수동 실행
5. fallback EC2에서 `bash scripts/deploy-be.sh` 수동 실행
6. API EC2에서 `docker compose -f shared/compose.api.prod.yml -f be-api/compose.prod.yml ps`
7. `curl http://127.0.0.1/healthz`
8. API / Worker 로그에서 Flyway migration, datasource 연결, RabbitMQ 연결 확인

### 알림 SSE 점검

알림 SSE는 `GET /api/v1/notifications/subscribe`를 사용한다. 브라우저 `EventSource`가
Authorization 헤더를 설정할 수 없으므로 access token을 `token` query parameter로 전달한다.
토큰 값은 명령 기록이나 공유 로그에 남기지 않는다.

```bash
read -s MEETBOWL_TEST_ACCESS_TOKEN
curl -kN \
  -H 'Accept: text/event-stream' \
  --get \
  --data-urlencode "token=${MEETBOWL_TEST_ACCESS_TOKEN}" \
  https://127.0.0.1/api/v1/notifications/subscribe
unset MEETBOWL_TEST_ACCESS_TOKEN
```

확인 항목:

1. 연결 직후 `event: ping`, `data: connected`가 즉시 전달된다.
2. 연결 유지 중 약 30초마다 `event: ping`, `data: keepalive`가 전달된다.
3. 알림 생성 시 `event: notification`이 buffering 없이 전달된다.
4. Nginx access log에 `/api/v1/notifications/subscribe?token=...` 요청이 남지 않는다.
5. 약 30분 후 BE emitter timeout으로 연결이 종료되며 브라우저 `EventSource`가 재접속한다.

---

## 오늘 기준 남은 작업

`meetbowl-be` 운영 배포 기준으로 남은 핵심 작업은 아래다.

1. SSM 실제 값 등록
2. EC2 IAM role 부여
3. Nginx 인증서 배치
4. 수동 `deploy-be.sh` 1회 검증
5. 수동 `deploy-be-api.sh` 1회 검증
6. 수동 `deploy-be-worker.sh` 1회 검증
7. API ASG user data / 부팅 훅 검증
8. GitHub Actions secret 등록
9. `main` 기준 자동 배포 테스트
