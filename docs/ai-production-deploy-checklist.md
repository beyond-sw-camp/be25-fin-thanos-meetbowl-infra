# Meetbowl AI Production Deploy Checklist

## 목적

이 문서는 `meetbowl-ai` 운영 배포에 필요한 실제 등록값과 서버 준비 항목만 정리한다.

대상 범위는 아래로 한정한다.

- `meetbowl-ai`
- `shared/compose.prod.yml`
- `ai/compose.prod.yml`
- `scripts/deploy-ai.sh`

---

## 배포 구조

운영 배포는 아래 순서로 진행된다.

1. GitHub Actions가 `meetbowl-ai` 이미지를 ECR에 push한다.
2. GitHub Actions가 EC2에 SSH 접속한다.
3. EC2의 `meetbowl-infra/scripts/deploy-ai.sh`가 SSM Parameter Store 값을 읽는다.
4. `shared/compose.prod.yml + ai/compose.prod.yml` 조합으로 `docker compose up -d ai`를 실행한다.
5. `http://127.0.0.1:${MEETBOWL_AI_PORT:-8000}/api/v1/health/ready` smoke test가 통과하면 배포 완료로 본다.

---

## SSM Prefix

운영 SSM Parameter Store는 아래 prefix를 사용한다.

```text
/meetbowl/prod/shared
/meetbowl/prod/ai
```

`deploy-ai.sh`는 위 두 prefix를 읽어 `.runtime/shared.env`, `.runtime/ai.env`를 만든 뒤 shell 환경변수로 로드한다.

---

## 필수 Shared 파라미터

아래 값은 `shared/compose.prod.yml` 또는 `ai/compose.prod.yml`에서 직접 사용된다.

| SSM Key | 예시 값 | 용도 |
|---|---|---|
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_USER` | `meetbowl` | shared compose 운영 계정 |
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_PASS` | `********` | RabbitMQ 비밀번호 |

아래 값은 기본값이 있으나 운영에서는 명시 등록을 권장한다.

| SSM Key | 기본값 | 비고 |
|---|---|---|
| `/meetbowl/prod/shared/REDIS_PORT` | `6379` | shared compose localhost bind |
| `/meetbowl/prod/shared/REDIS_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/RABBITMQ_AMQP_PORT` | `5672` | |
| `/meetbowl/prod/shared/RABBITMQ_AMQP_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/RABBITMQ_MANAGEMENT_PORT` | `15672` | |
| `/meetbowl/prod/shared/RABBITMQ_MANAGEMENT_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_VHOST` | `/` | |
| `/meetbowl/prod/shared/QDRANT_HTTP_PORT` | `6333` | |
| `/meetbowl/prod/shared/QDRANT_HTTP_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/QDRANT_GRPC_PORT` | `6334` | |
| `/meetbowl/prod/shared/QDRANT_GRPC_BIND_ADDRESS` | `127.0.0.1` | |

---

## 필수 AI 파라미터

아래 값은 `deploy-ai.sh`가 누락 시 즉시 실패 처리한다.

| SSM Key | 예시 값 | 용도 |
|---|---|---|
| `/meetbowl/prod/ai/INTERNAL_TOKEN` | `********` | BE internal 호출 인증 토큰 |
| `/meetbowl/prod/ai/BE_BASE_URL` | `http://be:8080` | AI가 BE internal context API 호출할 주소 |
| `/meetbowl/prod/ai/GEMINI_API_KEY` | `AIza...` | 회의록/챗봇/추출 모델 인증 |
| `/meetbowl/prod/ai/OPENAI_API_KEY` | `sk-...` | 기본 임베딩 모델 인증 |
| `/meetbowl/prod/ai/RABBITMQ_URL` | `amqp://meetbowl:***@rabbitmq:5672/` | 회의록/문서 색인 consumer 연결 |
| `/meetbowl/prod/ai/REDIS_URL` | `redis://redis:6379` | Redis feedback / idempotency 연결 |
| `/meetbowl/prod/ai/QDRANT_URL` | `http://qdrant:6333` | 내부 Qdrant 연결 |
| `/meetbowl/prod/ai/S3_BUCKET` | `meetbowl-prod-files` | 드라이브/공유 파일 원본 저장소 |
| `/meetbowl/prod/ai/AWS_REGION` | `ap-northeast-2` | S3 region |

아래 값은 기본값이 있으나 운영에서는 명시 등록을 권장한다.

| SSM Key | 기본값 | 비고 |
|---|---|---|
| `/meetbowl/prod/ai/RABBITMQ_ENABLED` | `true` | 운영에서는 Rabbit consumer 활성화 권장 |
| `/meetbowl/prod/ai/REDIS_FEEDBACK_ENABLED` | `true` | 운영에서는 실시간 피드백 활성화 권장 |
| `/meetbowl/prod/ai/MEETBOWL_AI_BIND_ADDRESS` | `127.0.0.1` | 외부 직접 비노출 |
| `/meetbowl/prod/ai/MEETBOWL_AI_PORT` | `8000` | EC2 내부 smoke test용 |
| `/meetbowl/prod/ai/RABBITMQ_EXCHANGE` | `meetbowl.topic` | |
| `/meetbowl/prod/ai/RABBITMQ_MINUTES_GENERATE_QUEUE` | `ai.minutes.generate` | |
| `/meetbowl/prod/ai/RABBITMQ_MINUTES_REGENERATE_QUEUE` | `ai.minutes.regenerate` | |
| `/meetbowl/prod/ai/RABBITMQ_DOCUMENT_INDEX_QUEUE` | `ai.index.document` | |
| `/meetbowl/prod/ai/RABBITMQ_DOCUMENT_INDEX_REMOVED_QUEUE` | `ai.index.document.removed` | |
| `/meetbowl/prod/ai/RABBITMQ_MINUTES_GENERATED_ROUTING_KEY` | `minutes.generated` | |
| `/meetbowl/prod/ai/RABBITMQ_MAX_RETRIES` | `3` | |
| `/meetbowl/prod/ai/REDIS_FEEDBACK_CONSUMER_GROUP` | `ai-feedback` | |
| `/meetbowl/prod/ai/REDIS_FEEDBACK_CONSUMER_NAME` | `ai-prod` | 다중 인스턴스면 구분 필요 |
| `/meetbowl/prod/ai/REDIS_FEEDBACK_STREAM_MAX_LENGTH` | `2000` | |
| `/meetbowl/prod/ai/REDIS_FEEDBACK_SCAN_INTERVAL_SECONDS` | `1.0` | |
| `/meetbowl/prod/ai/OPENAI_BASE_URL` | `https://api.openai.com/v1` | |
| `/meetbowl/prod/ai/MINUTES_SUMMARY_MODEL` | `gemini-2.5-flash` | |
| `/meetbowl/prod/ai/CHATBOT_MODEL` | `gemini-2.5-flash` | |
| `/meetbowl/prod/ai/DOCUMENT_EMBEDDING_MODEL` | `text-embedding-3-large` | |
| `/meetbowl/prod/ai/DOCUMENT_EMBEDDING_DIMENSIONS` | `1536` | query와 동일해야 함 |
| `/meetbowl/prod/ai/QUERY_EMBEDDING_MODEL` | `text-embedding-3-large` | |
| `/meetbowl/prod/ai/QUERY_EMBEDDING_DIMENSIONS` | `1536` | document와 동일해야 함 |
| `/meetbowl/prod/ai/QDRANT_COLLECTION` | `meetbowl-documents-openai-large-1536` | 임베딩 모델 변경 시 새 collection 필요 |
| `/meetbowl/prod/ai/DOCUMENT_CHUNK_SIZE` | `1200` | |
| `/meetbowl/prod/ai/DOCUMENT_CHUNK_OVERLAP` | `150` | |
| `/meetbowl/prod/ai/DOCUMENT_CHUNK_STRATEGY_VERSION` | `paragraph-v1` | |
| `/meetbowl/prod/ai/DOCUMENT_EXTRACTION_MODEL` | `gemini-2.5-flash` | |
| `/meetbowl/prod/ai/BE_CONTEXT_TIMEOUT_SECONDS` | `5.0` | |
| `/meetbowl/prod/ai/S3_ENDPOINT` | 빈 값 | AWS S3면 비워둘 수 있음 |
| `/meetbowl/prod/ai/AWS_ACCESS_KEY_ID` | 빈 값 | EC2 IAM Role 사용 시 불필요 |
| `/meetbowl/prod/ai/AWS_SECRET_ACCESS_KEY` | 빈 값 | EC2 IAM Role 사용 시 불필요 |
| `/meetbowl/prod/ai/FEEDBACK_WINDOW_MAX_SEGMENTS` | `8` | |
| `/meetbowl/prod/ai/FEEDBACK_WINDOW_MAX_SECONDS` | `45` | |
| `/meetbowl/prod/ai/FEEDBACK_MIN_SEGMENTS` | `4` | |
| `/meetbowl/prod/ai/FEEDBACK_MIN_WINDOW_CHARS` | `40` | |
| `/meetbowl/prod/ai/FEEDBACK_TRIGGER_INTERVAL_SECONDS` | `15` | |
| `/meetbowl/prod/ai/FEEDBACK_COOLDOWN_SECONDS` | `90` | |
| `/meetbowl/prod/ai/FEEDBACK_STATE_TTL_SECONDS` | `300` | |
| `/meetbowl/prod/ai/FEEDBACK_SCORE_THRESHOLD` | `0.78` | |
| `/meetbowl/prod/ai/FEEDBACK_CANDIDATE_LIMIT` | `3` | |
| `/meetbowl/prod/ai/CHAT_SCORE_THRESHOLD` | `0.0` | |
| `/meetbowl/prod/ai/CHAT_DOCUMENT_MAX_CHARS` | `16000` | |
| `/meetbowl/prod/ai/CHAT_THINKING_BUDGET` | `512` | 지연 민감하면 더 낮출 수 있음 |
| `/meetbowl/prod/ai/RERANK_CANDIDATE_POOL` | `30` | |
| `/meetbowl/prod/ai/RERANK_TOP_N` | `10` | |

`INTERNAL_TOKEN` 값은 `meetbowl-be`의 `MEETBOWL_INTERNAL_TOKEN`과 동일해야 한다.
`BE_BASE_URL`은 `be` compose service 기준 `http://be:8080`을 권장한다.

---

## GitHub Secrets

`meetbowl-ai` GitHub Actions는 아래 secret을 요구한다.

| Secret | 용도 |
|---|---|
| `AWS_GITHUB_ACTIONS_ROLE_ARN` | GitHub OIDC로 ECR push 및 배포 권한 획득 |
| `MEETBOWL_EC2_HOST` | EC2 접속 호스트 |
| `MEETBOWL_EC2_USER` | SSH 사용자 |
| `MEETBOWL_EC2_SSH_KEY` | private key |
| `MEETBOWL_DEPLOY_PATH` | EC2의 `meetbowl-infra` 루트 경로 |

`MEETBOWL_DEPLOY_PATH`는 반드시 아래처럼 infra 레포 루트여야 한다.

```text
/opt/meetbowl/meetbowl-infra
```

---

## EC2 사전 준비

아래는 `meetbowl-ai` 첫 배포 전에 완료되어야 한다.

1. `meetbowl-infra`가 EC2에 clone 되어 있어야 한다.
2. `docker`, `docker compose`, `aws cli`, `curl`이 설치되어 있어야 한다.
3. EC2 instance profile 또는 attached role에 아래 권한이 있어야 한다.

```text
ssm:GetParametersByPath
ssm:GetParameters
kms:Decrypt
ecr:GetAuthorizationToken
ecr:BatchGetImage
ecr:GetDownloadUrlForLayer
sts:GetCallerIdentity
```

4. `shared/compose.prod.yml`의 `redis`, `rabbitmq`, `qdrant`가 먼저 정상 기동 가능한 상태여야 한다.
5. `meetbowl-be`와 `meetbowl-ai`의 internal token 값이 동기화되어 있어야 한다.

---

## 첫 배포 전 수동 점검

GitHub Actions 자동 배포 전에 EC2에서 아래를 먼저 확인하는 편이 안전하다.

1. `aws ssm get-parameters-by-path --path /meetbowl/prod/shared --with-decryption`
2. `aws ssm get-parameters-by-path --path /meetbowl/prod/ai --with-decryption`
3. `bash scripts/deploy-ai.sh` 수동 실행
4. `docker compose -f shared/compose.prod.yml -f ai/compose.prod.yml ps`
5. `curl http://127.0.0.1:8000/api/v1/health`
6. `curl http://127.0.0.1:8000/api/v1/health/ready`
7. AI 로그에서 Qdrant/Redis/RabbitMQ 연결 성공과 env validation 확인

---

## 오늘 기준 남은 작업

`meetbowl-ai` 운영 배포 기준으로 남은 핵심 작업은 아래다.

1. `/meetbowl/prod/ai` 실제 SSM 값 등록
2. `meetbowl-be`의 `MEETBOWL_AI_BASE_URL`, `MEETBOWL_INTERNAL_TOKEN`과 값 정합성 확인
3. EC2 IAM role 부여
4. 수동 `deploy-ai.sh` 1회 검증
5. GitHub Actions secret 등록
6. `main` 기준 자동 배포 테스트
