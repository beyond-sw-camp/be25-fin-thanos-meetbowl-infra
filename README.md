# Meetbowl Infra

Meetbowl 로컬 개발에 필요한 공용 런타임을 Docker Compose로 실행한다.

이 레포는 실행 환경만 담당한다. 비즈니스 로직, API 계약, 이벤트 이름, DB 스키마 소유권은 각 서버와 루트 문서를 따른다.

운영 배포 구조를 확정한 문서는 [docs/production-deployment-architecture.md](./docs/production-deployment-architecture.md) 를 참고한다.

운영 compose는 `shared/compose.prod.yml`, `shared/compose.api.prod.yml`와 서비스별 overlay(`be/compose.prod.yml`, `be-api/compose.prod.yml`, `be-worker/compose.prod.yml` 등)로 분리한다.
운영 배포 스크립트는 `scripts/deploy-be.sh`, `scripts/deploy-be-api.sh`, `scripts/deploy-be-worker.sh`, `scripts/deploy-be-split.sh`처럼 infra 레포 루트를 기준으로 실행한다.

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

LiveKit/STT를 같이 테스트할 때는 현재 호스트 IP를 자동 주입하는 wrapper를 우선 사용한다.

```bash
./scripts/compose-with-livekit-ip.sh --profile stt up -d
```

STT 서버까지 실행하려면 실제 `OPENAI_API_KEY`를 로컬 `.env`에 주입한 뒤 profile을
사용한다.

```bash
docker compose --profile stt up -d
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
| LiveKit public URL | `http://localhost:7880` |
| STT API(profile 사용 시) | `http://localhost:3000` |
| Qdrant | `http://localhost:6333` |

RabbitMQ Management 기본 계정:

```text
meetbowl / local-rabbitmq-password
```

이 계정은 `.env`의 `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS`,
`RABBITMQ_DEFAULT_VHOST`로 설정한다. `rabbitmq/definitions.json`은 exchange,
queue, binding만 정의하고 비밀번호 해시는 고정하지 않는다.

LiveKit 로컬 개발 키는 `.env`에서 런타임에 주입한다.

```text
LIVEKIT_API_KEY / LIVEKIT_API_SECRET
```

사용자 회의 참여 토큰 발급은 `meetbowl-be` 책임이다. infra에 별도 token-server를 두지 않는다.
`meetbowl-stt`는 같은 key/secret으로 server participant token을 생성하되, secret을
프론트에 전달하지 않는다.

LiveKit은 Docker 내부 IP를 ICE candidate로 광고하지 않도록 `NODE_IP`를 명시적으로
주입한다. STT를 호스트에서 실행하면 `LIVEKIT_NODE_IP=127.0.0.1`을 사용할 수 있다.
STT까지 Compose profile로 실행할 때는 브라우저가 실행되는 호스트와 Docker 컨테이너
양쪽에서 접근 가능한 LAN IP를 `LIVEKIT_NODE_IP`로 지정해야 한다. RTC TCP `7881`과
UDP `7882`도 해당 IP에서 접근 가능해야 한다.

로컬에서 네트워크가 자주 바뀌면 `.env`에 IP를 하드코딩하지 말고 아래 wrapper를 사용한다.
이 스크립트는 macOS 기본 네트워크 인터페이스의 IPv4를 감지해서 `LIVEKIT_NODE_IP` 환경
변수로 `docker compose`에 주입한다.

```bash
./scripts/compose-with-livekit-ip.sh up -d livekit
./scripts/compose-with-livekit-ip.sh --profile stt up -d livekit stt
```

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
api.minutes.generated
ai.minutes.generate
ai.minutes.regenerate
ai.index.document
```

각 queue에는 `meetbowl.dlx`로 dead-letter 설정이 들어가며, DLQ는 운영 확인용으로 별도 생성한다.

`api.transcript.final.save`는 quorum queue이며 `x-delivery-limit=3`을 사용한다. Consumer가
처리에 실패해 메시지를 재전달하면 delivery limit 이후
`dlq.api.transcript.final.save`로 이동한다. STT publisher는 persistent message와
publisher confirm을 사용해야 한다.

기존 로컬 볼륨에 classic `api.transcript.final.save` queue가 이미 있으면 queue type은
제자리에서 quorum으로 변경되지 않는다. 로컬 데이터 삭제가 허용되는 경우
`docker compose down -v` 후 다시 시작해야 새 정의가 적용된다.

## Redis Stream 기준

Redis Stream은 서버 내부 실시간 처리 흐름에만 사용한다.

문서 기준 stream:

```text
meeting:{meetingId}:feedback-source
meeting:{meetingId}:feedback-result
meeting:{meetingId}:status
```

Redis Stream 이벤트는 장기 보관 데이터가 아니다. 최종 저장이 필요한 데이터는 RabbitMQ 또는 `meetbowl-be` REST API를 통해 저장한다.

STT는 `meeting.feedback.segment.created`를 segment 한 건씩 발행한다. AI 서버가
meeting별 rolling window를 구성한다. Stream producer는 approximate `MAXLEN`을 사용해
무제한 증가를 방지한다.

## STT 연결 URL

호스트에서 STT를 실행할 때:

```text
LIVEKIT_URL=http://localhost:7880
RABBITMQ_URL=amqp://meetbowl:...@localhost:5672/
REDIS_URL=redis://localhost:6379
```

Compose profile에서 실행할 때는 service name 기반 URL을 자동으로 사용한다.

```text
LIVEKIT_URL=http://livekit:7880
RABBITMQ_URL=amqp://meetbowl:...@rabbitmq:5672/
REDIS_URL=redis://redis:6379
```

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
