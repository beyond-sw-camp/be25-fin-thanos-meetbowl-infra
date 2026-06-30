# Meetbowl STT Production Deploy Checklist

## 목적

이 문서는 `meetbowl-stt` 운영 배포에 필요한 실제 등록값과 서버 준비 항목만 정리한다.

대상 범위는 아래로 한정한다.

- `meetbowl-stt`
- `shared/compose.prod.yml`
- `stt/compose.prod.yml`
- `scripts/deploy-stt.sh`

---

## 배포 구조

운영 배포는 아래 순서로 진행된다.

1. GitHub Actions가 `meetbowl-stt` 이미지를 ECR에 push한다.
2. GitHub Actions가 EC2에 SSH 접속한다.
3. EC2의 `meetbowl-infra/scripts/deploy-stt.sh`가 SSM Parameter Store 값을 읽는다.
4. `shared/compose.prod.yml + stt/compose.prod.yml` 조합으로 `docker compose up -d stt`를 실행한다.
5. `http://127.0.0.1:${MEETBOWL_STT_PORT:-3000}/api/v1/health`와 `/api/v1/health/provider` smoke test가 통과하면 배포 완료로 본다.

---

## SSM Prefix

운영 SSM Parameter Store는 아래 prefix를 사용한다.

```text
/meetbowl/prod/shared
/meetbowl/prod/stt
```

`deploy-stt.sh`는 위 두 prefix를 읽어 `.runtime/shared.env`, `.runtime/stt.env`를 만든 뒤 shell 환경변수로 로드한다.

---

## 필수 Shared 파라미터

아래 값은 `shared/compose.prod.yml` 또는 `stt/compose.prod.yml`에서 직접 사용된다.

| SSM Key | 예시 값 | 용도 |
|---|---|---|
| `/meetbowl/prod/shared/LIVEKIT_API_KEY` | `prod-livekit-key` | STT가 LiveKit에 server participant로 접속할 때 사용 |
| `/meetbowl/prod/shared/LIVEKIT_API_SECRET` | `********` | LiveKit secret |
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_USER` | `meetbowl` | shared compose 운영 계정 |
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_PASS` | `********` | RabbitMQ 비밀번호 |

아래 값은 기본값이 있으나 운영에서는 명시 등록을 권장한다.

| SSM Key | 기본값 | 비고 |
|---|---|---|
| `/meetbowl/prod/shared/REDIS_PORT` | `6379` | shared compose에서 localhost bind |
| `/meetbowl/prod/shared/REDIS_BIND_ADDRESS` | `127.0.0.1` | 외부 직접 비노출 권장 |
| `/meetbowl/prod/shared/RABBITMQ_AMQP_PORT` | `5672` | |
| `/meetbowl/prod/shared/RABBITMQ_AMQP_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/RABBITMQ_MANAGEMENT_PORT` | `15672` | |
| `/meetbowl/prod/shared/RABBITMQ_MANAGEMENT_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/RABBITMQ_DEFAULT_VHOST` | `/` | |
| `/meetbowl/prod/shared/LIVEKIT_HTTP_PORT` | `7880` | |
| `/meetbowl/prod/shared/LIVEKIT_HTTP_BIND_ADDRESS` | `127.0.0.1` | |
| `/meetbowl/prod/shared/LIVEKIT_RTC_TCP_PORT` | `7881` | 보안그룹 확인 |
| `/meetbowl/prod/shared/LIVEKIT_RTC_UDP_PORT` | `7882` | 보안그룹 확인 |

---

## 필수 STT 파라미터

아래 값은 `deploy-stt.sh`가 누락 시 즉시 실패 처리한다.

| SSM Key | 예시 값 | 용도 |
|---|---|---|
| `/meetbowl/prod/stt/INTERNAL_TOKEN` | `********` | BE가 STT internal API 호출 시 맞춰야 하는 토큰. 권장 표준 키 |
| `/meetbowl/prod/stt/OPENAI_API_KEY` | `sk-...` | OpenAI Realtime 인증 |
| `/meetbowl/prod/stt/RABBITMQ_URL` | `amqp://meetbowl:***@rabbitmq:5672/` | finalized transcript 발행 경로 |
| `/meetbowl/prod/stt/REDIS_URL` | `redis://redis:6379` | Redis Stream 연결 |

아래 값은 기본값이 있으나 운영에서는 명시 등록을 권장한다.

| SSM Key | 기본값 | 비고 |
|---|---|---|
| `/meetbowl/prod/stt/HOST` | `0.0.0.0` | 컨테이너 내부 bind |
| `/meetbowl/prod/stt/PORT` | `3000` | 컨테이너 내부 포트 |
| `/meetbowl/prod/stt/MEETBOWL_STT_BIND_ADDRESS` | `0.0.0.0` | 다른 EC2에서 private IP로 접근할 수 있게 호스트 NIC에 bind |
| `/meetbowl/prod/stt/MEETBOWL_STT_PORT` | `3000` | EC2 내부 smoke test용 |
| `/meetbowl/prod/stt/ENABLE_TRANSLATION` | `false` | 운영 번역 활성화 스위치 |
| `/meetbowl/prod/stt/OPENAI_REALTIME_TRANSLATION_MODEL` | `gpt-realtime-translate` | |
| `/meetbowl/prod/stt/OPENAI_REALTIME_TRANSCRIPTION_MODEL` | `gpt-realtime-whisper` | |
| `/meetbowl/prod/stt/OPENAI_REALTIME_TRANSCRIPTION_DELAY` | `medium` | |
| `/meetbowl/prod/stt/LIVEKIT_URL` | `http://livekit:7880` | shared runtime service name 기준 |
| `/meetbowl/prod/stt/LIVEKIT_AGENT_IDENTITY_PREFIX` | `meetbowl-stt` | |
| `/meetbowl/prod/stt/RABBITMQ_EXCHANGE` | `meetbowl.topic` | |
| `/meetbowl/prod/stt/REDIS_FEEDBACK_CONSUMER_GROUP` | `stt-feedback-relay` | |
| `/meetbowl/prod/stt/REDIS_FEEDBACK_CONSUMER_NAME` | `stt-prod` | 다중 인스턴스면 구분 필요 |
| `/meetbowl/prod/stt/REDIS_STREAM_MAX_LENGTH` | `2000` | |
| `/meetbowl/prod/stt/VAD_RMS_THRESHOLD` | `0.008` | |
| `/meetbowl/prod/stt/VAD_SILENCE_MS` | `520` | |
| `/meetbowl/prod/stt/SEGMENT_NO_DELTA_TIMEOUT_MS` | `1600` | |
| `/meetbowl/prod/stt/TRANSLATION_GRACE_MS` | `480` | |
| `/meetbowl/prod/stt/MAX_SEGMENT_DURATION_MS` | `9000` | |
| `/meetbowl/prod/stt/STREAMING_PUBLISH_MIN_INTERVAL_MS` | `320` | |
| `/meetbowl/prod/stt/TRACK_SWITCH_GRACE_MS` | `120` | |

`INTERNAL_TOKEN` 값은 `meetbowl-be`의 `MEETBOWL_STT_INTERNAL_TOKEN`과 동일해야 한다.
운영 전환 중이라면 임시로 `/meetbowl/prod/stt/STT_INTERNAL_TOKEN` 또는
`/meetbowl/prod/stt/MEETBOWL_STT_INTERNAL_TOKEN`도 읽도록 호환되어 있지만, 최종 표준은
`/meetbowl/prod/stt/INTERNAL_TOKEN` 하나로 정리하는 편이 낫다.

---

## GitHub Secrets

`meetbowl-stt` GitHub Actions는 아래 secret을 요구한다.

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

아래는 `meetbowl-stt` 첫 배포 전에 완료되어야 한다.

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

4. `shared/compose.prod.yml`의 `redis`, `rabbitmq`, `livekit`가 먼저 정상 기동 가능한 상태여야 한다.
5. `meetbowl-be`에서 STT 호출 시 사용할 internal token 값이 동기화되어 있어야 한다.

---

## 첫 배포 전 수동 점검

GitHub Actions 자동 배포 전에 EC2에서 아래를 먼저 확인하는 편이 안전하다.

1. `aws ssm get-parameters-by-path --path /meetbowl/prod/shared --with-decryption`
2. `aws ssm get-parameters-by-path --path /meetbowl/prod/stt --with-decryption`
3. `bash scripts/deploy-stt.sh` 수동 실행
4. `docker compose -f shared/compose.prod.yml -f stt/compose.prod.yml ps`
5. `curl http://127.0.0.1:3000/api/v1/health`
6. `curl http://127.0.0.1:3000/api/v1/health/provider`
7. STT 로그에서 Redis/RabbitMQ 연결 성공과 env validation 성공 확인

---

## 오늘 기준 남은 작업

`meetbowl-stt` 운영 배포 기준으로 남은 핵심 작업은 아래다.

1. `/meetbowl/prod/stt` 실제 SSM 값 등록
2. `meetbowl-be`의 `MEETBOWL_STT_BASE_URL`, `MEETBOWL_STT_INTERNAL_TOKEN`과 값 정합성 확인
3. EC2 IAM role 부여
4. 수동 `deploy-stt.sh` 1회 검증
5. GitHub Actions secret 등록
6. `main` 기준 자동 배포 테스트
