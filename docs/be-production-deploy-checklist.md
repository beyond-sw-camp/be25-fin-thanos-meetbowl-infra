# Meetbowl BE Production Deploy Checklist

## 목적

이 문서는 `meetbowl-be` 운영 배포에 필요한 실제 등록값과 서버 준비 항목만 정리한다.

대상 범위는 아래로 한정한다.

- `meetbowl-be`
- `shared/compose.prod.yml`
- `be/compose.prod.yml`
- `scripts/deploy-be.sh`

`meetbowl-ai`, `meetbowl-stt`는 같은 패턴을 재사용하되 이 문서 범위에는 포함하지 않는다.

---

## 배포 구조

운영 배포는 아래 순서로 진행된다.

1. GitHub Actions가 `meetbowl-be` 이미지를 ECR에 push한다.
2. GitHub Actions가 EC2에 SSH 접속한다.
3. EC2의 `meetbowl-infra/scripts/deploy-be.sh`가 SSM Parameter Store 값을 읽는다.
4. `shared/compose.prod.yml + be/compose.prod.yml` 조합으로 `docker compose up -d`를 실행한다.
5. Nginx `/healthz` smoke test가 통과하면 배포 완료로 본다.

---

## SSM Prefix

운영 SSM Parameter Store는 아래 prefix를 사용한다.

```text
/meetbowl/prod/shared
/meetbowl/prod/be
```

`deploy-be.sh`는 위 두 prefix를 읽어 `.runtime/shared.env`, `.runtime/be.env`를 만든 뒤 shell 환경변수로 로드한다.

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
| `/meetbowl/prod/be/MEETBOWL_LIVEKIT_URL` | `http://livekit:7880` | 내부 네트워크 기준 |
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

---

## GitHub Secrets

`meetbowl-be` GitHub Actions는 아래 secret을 요구한다.

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

아래는 `meetbowl-be` 첫 배포 전에 완료되어야 한다.

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

4. `NGINX_CERTS_DIR` 경로에 아래 파일이 있어야 한다.

```text
fullchain.pem
privkey.pem
```

5. RDS security group inbound는 EC2 security group에서만 `3306/tcp` 허용 상태여야 한다.

---

## 첫 배포 전 수동 점검

GitHub Actions 자동 배포 전에 EC2에서 아래를 먼저 확인하는 편이 안전하다.

1. `aws ssm get-parameters-by-path --path /meetbowl/prod/shared --with-decryption`
2. `aws ssm get-parameters-by-path --path /meetbowl/prod/be --with-decryption`
3. `bash scripts/deploy-be.sh` 수동 실행
4. `docker compose -f shared/compose.prod.yml -f be/compose.prod.yml ps`
5. `curl -k https://127.0.0.1/healthz`
6. BE 로그에서 Flyway migration, datasource 연결, RabbitMQ 연결 확인

---

## 오늘 기준 남은 작업

`meetbowl-be` 운영 배포 기준으로 남은 핵심 작업은 아래다.

1. SSM 실제 값 등록
2. EC2 IAM role 부여
3. Nginx 인증서 배치
4. 수동 `deploy-be.sh` 1회 검증
5. GitHub Actions secret 등록
6. `main` 기준 자동 배포 테스트
