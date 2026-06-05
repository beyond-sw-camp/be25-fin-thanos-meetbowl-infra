# Meetbowl Infra

Meetbowl 로컬 개발에 필요한 공용 런타임을 Docker Compose로 실행한다.

이 레포는 실행 환경만 담당한다. 비즈니스 로직, API 계약, 이벤트 이름, DB 스키마 소유권은 각 서버와 루트 문서를 따른다.

## 구성

| Service | Port | Owner / Purpose |
|---|---:|---|
| MariaDB | `3306` | `meetbowl-be` 전용 업무 DB |
| Redis | `6379` | 캐시, 짧은 TTL 상태, Redis Stream |
| RabbitMQ | `5672`, `15672` | 반드시 처리되어야 하는 비동기 작업 큐 |
| LiveKit | `7880`, `7881`, `7882/udp` | 회의 media session, DataChannel |
| Qdrant | `6333`, `6334` | `meetbowl-ai` 전용 벡터 저장소 |
| S3 | external | 파일 원본 저장소 |

MinIO는 실행하지 않는다. 파일 원본은 외부 S3 또는 S3 호환 스토리지를 사용하고, 권한 검사와 파일 메타데이터 저장은 `meetbowl-be`가 담당한다.

## 시작

```bash
cp .env.example .env
docker compose up -d
```

상태 확인:

```bash
docker compose ps
docker compose logs -f rabbitmq
```

종료:

```bash
docker compose down
```

볼륨까지 초기화:

```bash
docker compose down -v
```

## 접속 정보

기본값은 로컬 개발 전용 예시다. 실제 비밀값을 커밋하지 않는다.

| Runtime | URL |
|---|---|
| MariaDB | `localhost:3306` |
| Redis | `redis://localhost:6379` |
| RabbitMQ AMQP | `amqp://meetbowl:local-rabbitmq-password@localhost:5672/` |
| RabbitMQ Management | `http://localhost:15672` |
| LiveKit | `http://localhost:7880` |
| Qdrant | `http://localhost:6333` |

RabbitMQ Management 기본 계정:

```text
meetbowl / local-rabbitmq-password
```

이 계정은 `rabbitmq/definitions.json`에 로컬 개발용 계정으로 정의되어 있다. 비밀번호를 바꾸려면 `.env`의 URL만 바꾸지 말고 RabbitMQ definitions의 user hash도 함께 갱신해야 한다.

LiveKit 로컬 개발 키:

```text
devkey / secret
```

사용자 회의 참여 토큰 발급은 `meetbowl-be` 책임이다. infra에 별도 token-server를 두지 않는다.

## RabbitMQ 계약

RabbitMQ 설정은 `docs/event-contract.md`의 Exchange / Queue 기준을 반영한다.

Exchange:

```text
meetbowl.topic
meetbowl.dlx
```

Queue:

```text
api.transcript.final.save
ai.minutes.generate
ai.minutes.regenerate
ai.index.document
```

각 queue에는 `meetbowl.dlx`로 dead-letter 설정이 들어가며, DLQ는 운영 확인용으로 별도 생성한다.

## Redis Stream 기준

Redis Stream은 서버 내부 실시간 처리 흐름에만 사용한다.

문서 기준 stream:

```text
meeting:{meetingId}:feedback-source
meeting:{meetingId}:feedback-result
meeting:{meetingId}:status
```

Redis Stream 이벤트는 장기 보관 데이터가 아니다. 최종 저장이 필요한 데이터는 RabbitMQ 또는 `meetbowl-be` REST API를 통해 저장한다.

## S3 기준

`.env.example`에는 S3 접속값의 예시만 둔다.

```text
AWS_REGION
S3_BUCKET
S3_ENDPOINT
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

AWS S3를 쓰면 `S3_ENDPOINT`는 비워둘 수 있다. S3 호환 스토리지를 쓰는 경우 해당 endpoint를 지정한다.

## 포트 충돌

다른 로컬 컨테이너가 기본 포트를 이미 사용 중이면 `.env`에서 호스트 포트만 바꿔 실행할 수 있다.

예시:

```bash
REDIS_PORT=6381 \
RABBITMQ_AMQP_PORT=5673 \
RABBITMQ_MANAGEMENT_PORT=15673 \
docker compose up -d
```

컨테이너 내부 포트는 그대로 유지되므로 같은 Docker network에서 붙는 애플리케이션은 서비스명과 내부 포트를 사용할 수 있다.

## 금지 사항

- infra 레포에 비즈니스 로직 작성 금지
- 이벤트 이름 임의 추가 금지
- RabbitMQ와 Redis Stream 역할 혼용 금지
- Redis Stream을 장기 저장소로 사용 금지
- 실제 비밀값 커밋 금지
- `meetbowl-ai`, `meetbowl-stt`의 MariaDB 직접 접근 금지
