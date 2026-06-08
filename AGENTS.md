# Meetbowl Infra AGENTS

## 목적

본 문서는 `meetbowl-infra`에서 작업하는 모든 개발자와 AI Agent가 반드시 따라야 하는 규칙을 정의한다.

---

## 필수 문서

작업 전 반드시 아래 문서를 읽는다.

```text
../AGENTS.md
../docs/architecture.md
../docs/conventions.md
../docs/event-contract.md
../docs/communication-decision.md
README.md
```

---

## 역할

`meetbowl-infra`는 Meetbowl 실행 환경과 로컬/배포 인프라 구성을 담당한다.

담당 범위:

- Docker Compose
- MariaDB
- Redis
- RabbitMQ
- LiveKit
- S3 호환 Object Storage
- 네트워크, 볼륨, 환경 변수 예시
- 로컬 개발 실행 문서

`meetbowl-infra`에는 비즈니스 로직을 작성하지 않는다.

---

## 데이터 소유권 기준

인프라는 저장소를 제공하지만 업무 데이터의 소유권을 갖지 않는다.

| 저장소 | 업무 소유 서버 |
|---|---|
| MariaDB | meetbowl-be |
| Qdrant | meetbowl-ai |
| Redis | Shared runtime, 장기 저장 금지 |
| RabbitMQ | Shared runtime, 비동기 작업 큐 |
| Object Storage | 파일 원본 저장소, 권한 검사는 meetbowl-be |
| LiveKit | meetbowl-stt 중심 연동 |

---

## 통신 / 메시징 기준

통신 방식 선택은 루트 `docs/communication-decision.md`를 따른다.

- 사용자 요청/조회/즉시 응답: REST API
- 반드시 처리되어야 하는 비동기 작업: RabbitMQ
- 서버 내부 실시간 이벤트 흐름: Redis Stream
- 회의 화면 실시간 자막, 피드백, 채팅: LiveKit DataChannel
- 파일 원본 저장: S3 호환 Object Storage

RabbitMQ Exchange/Queue, Redis Stream, LiveKit DataChannel 이벤트 이름은 루트 `docs/event-contract.md`를 단일 기준으로 삼는다.

---

## 환경 변수 / 비밀값 규칙

- 실제 비밀값을 커밋하지 않는다.
- `.env.example`에는 예시 값만 둔다.
- JWT Secret, DB 비밀번호, API Key, Object Storage Secret, LiveKit Secret은 로그와 문서에 노출하지 않는다.
- 로컬 기본 계정이 필요하면 운영 환경과 분리된 예시 값임을 명확히 한다.

---

## 금지 사항

```text
비즈니스 로직 작성
API 계약 임의 정의
이벤트 이름 임의 추가
MariaDB 스키마를 인프라 문서에서 단독 확정
Redis Stream을 장기 저장소로 구성
RabbitMQ와 Redis Stream 역할 혼용
실제 비밀값 커밋
```

---

## 구현 원칙

- 서비스명, 포트, 네트워크명, 볼륨명은 기존 Docker Compose 패턴을 우선 따른다.
- 인프라 변경이 서버 책임이나 이벤트 계약에 영향을 주면 루트 문서와 관련 서버 문서를 함께 갱신한다.
- 요구사항 관련 작업은 `FR-*`, `NFR-*` ID를 확인한다.
- 실행 방법이 바뀌면 `README.md`를 함께 갱신한다.
