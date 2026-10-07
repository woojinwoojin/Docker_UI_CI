# 4주차 — Docker + AWS EC2 배포

## 목표
3주차 서비스(FastAPI + Streamlit)를 컨테이너로 만들고 EC2에 배포해, 인터넷에서 접속할 수 있게 한다.
GitHub에 push할 때마다 테스트와 이미지 빌드가 자동으로 돌도록 **CI**(GitHub Actions)를 붙인다.

## 구조 (안)
```
git push ──► GitHub Actions (CI): pytest (Linux) → docker build   ← 실패하면 배포하지 않는다

내 브라우저 ──(내 IP만 허용)──► EC2 :8501
                                   │  docker compose
                                   ├─ ui  (Streamlit)  ──http://api:8000──►  api (FastAPI + Agent) ──► OpenAI
                                   │                                          │
                                   └──────────── volume: data/ (SQLite + 업로드 CSV + 예시 데이터) ◄──┘
```

## 문제 정의 (3주차 결과에서)
3주차 서비스는 내 컴퓨터에서 터미널 두 개로 띄운다. 인터넷에 올리려면 아래가 바뀌어야 한다.

| 3주차 (로컬) | 4주차에 필요한 것 |
|---|---|
| 터미널 두 개로 `uvicorn`, `streamlit`을 따로 실행 | 한 번에 띄우고 함께 관리 → **docker compose** |
| 화면이 `localhost:8000`으로 API를 찾음 | 컨테이너끼리는 서비스 이름으로 찾음 → `API_URL=http://api:8000` |
| `data/`(SQLite, 업로드 CSV)는 내 디스크 | 컨테이너를 다시 만들어도 남아야 함 → **volume** |
| API 키는 `.env` 파일 | 이미지·git에 절대 넣지 않고 **실행할 때** 전달 |
| `--reload` 개발 서버 | 운영 실행 (reload 없음, 재부팅 후 자동 시작) |
| 나만 접속 | **인증이 없다** → 공개하면 누구나 내 OpenAI 크레딧으로 질문할 수 있다 |
| Windows | EC2는 Linux. 경로·인코딩·CPU 아키텍처 차이 |
| 예시 데이터(Superstore)는 git에 없음 (Kaggle) | EC2로 따로 옮겨야 함 |
| 테스트는 내 컴퓨터(Windows)에서 손으로 실행 | push마다 **Linux에서 자동 실행** (CI) |
| 화면 테스트 8개는 `data/`가 없으면 **조용히 건너뜀** | CI에는 Superstore가 없으므로 그대로면 매번 건너뛴다 → 테스트용 작은 데이터 필요 |

## 정해야 할 설계 (내일 함께 결정, 괄호는 추천)
1. **저장소:** 주차별 규칙대로 새 저장소 + 3주차 코드 복사 (추천)
2. **이미지 구성:** Dockerfile 하나로 이미지 하나를 만들고, compose에서 `api`/`ui` 두 서비스가 실행 명령만 다르게 쓴다 (추천: 의존성이 같다)
   vs 서비스별 Dockerfile 두 개
3. **공개 범위:** 화면(8501)만 외부에 열고, API(8000)는 compose 내부망에만 둔다 (추천: 공격 면을 줄인다)
4. **최소 보호 (인증이 없으므로 필수)**
   - (a) EC2 보안 그룹에서 **내 IP만 허용** (추천, 필수)
   - (b) OpenAI 대시보드에서 **월 사용 한도** 설정 (추천, 필수)
   - (c) Streamlit 화면에 간단한 비밀번호 / (d) Nginx basic auth — 다른 사람에게 보여줄 때
5. **EC2 사양:** `t3.small`(2GB) (추천) vs `t3.micro`(1GB, 프리 티어)
   - pandas + Streamlit + FastAPI 두 컨테이너와 이미지 빌드에 1GB는 빠듯할 수 있다. micro로 가면 swap을 만든다
   - ARM(`t4g`)은 더 싸지만 이미지 아키텍처가 달라진다. 이미지를 EC2에서 직접 빌드하면 문제 없다
6. **배포 방식:** EC2에서 `git clone` → `docker compose up --build` (추천: 가장 단순)
   vs 이미지를 레지스트리(Docker Hub/ECR)에 올려 받기 — 프로젝트 5(CI/CD)에서
7. **비밀 값 전달:** EC2에 `.env`를 직접 만들고 compose의 `env_file`로 전달 (추천) vs AWS Secrets Manager (프로젝트 5)
8. **예시 데이터:** `scp`로 EC2의 data 폴더에 복사 (추천) vs 화면에서 업로드만 허용
9. **Nginx·HTTPS:** HTTPS는 도메인이 필요하다. 이번 주는 `http://IP:8501` + IP 제한으로 가고, 여유가 되면 Nginx (추천)
   - Nginx를 앞에 두면 Streamlit의 WebSocket 연결을 위한 설정이 따로 필요하다
10. **CI 범위:** push·PR마다 ① pytest ② `docker build`까지 (추천)
    - 테스트는 OpenAI를 부르지 않으므로 **GitHub Secrets에 API 키를 넣을 필요가 없다**
    - Linux에서 돌기 때문에 Windows에서만 통과하는 코드(경로, 인코딩)를 EC2에 올리기 전에 잡는다
    - 이미지를 레지스트리에 올리는 것(push)은 하지 않는다. EC2에서 직접 빌드하므로 필요 없다
11. **CI용 테스트 데이터:** 화면 테스트가 쓰는 예시 데이터를 어떻게 줄지
    - (a) Superstore와 같은 컬럼의 **작은 가짜 CSV**(수십 행)를 `tests/fixtures/`에 두고, 테스트에서 예시 데이터 경로를 그 파일로 바꾼다 (추천)
    - (b) 데이터가 없으면 지금처럼 건너뛴다 — CI가 초록불이어도 화면은 검사하지 않은 것이 된다
    - (c) Superstore를 저장소에 넣는다 — Kaggle 데이터 라이선스 확인이 필요하고 2.3MB가 git에 들어간다
12. **CD(자동 배포):** 이번 주는 **하지 않는다** (추천)
    - Actions가 EC2에 SSH로 들어가려면 보안 그룹을 GitHub IP 대역에 열어야 해서 "내 IP만 허용"과 충돌한다
    - 대신 EC2에서 `git pull` → `docker compose up -d --build`를 손으로 한다. 여유가 되면 확장 과제로 방법을 비교한다
13. **브랜치 규칙:** `main`에 바로 push (추천: 혼자 하는 프로젝트) vs PR + "CI 통과해야 병합" 보호 규칙 — 체험해 보고 싶다면 후자

## 함께 익힐 개념
- **Docker:** 이미지 vs 컨테이너, Dockerfile 레이어와 캐시(의존성 먼저 복사), `.dockerignore`, 포트 매핑, 환경 변수
- **Compose:** 서비스, 내부 네트워크와 서비스 이름 DNS, volume, `env_file`, `restart`, `depends_on`/healthcheck
- **EC2:** 리전, AMI, 인스턴스 유형, 키 페어와 SSH, 보안 그룹(방화벽), 퍼블릭 IP, 중지 vs 종료와 과금
- **Linux 운영:** 패키지 설치, `docker compose logs`, 디스크·메모리 확인(`df`, `free`), 재부팅 후 자동 시작
- **GitHub Actions:** workflow 파일(`.github/workflows/*.yml`), trigger(push·pull_request), job·step, runner(ubuntu), 의존성 캐시, 상태 배지
- **CI vs CD:** "합쳐도 되는가"를 자동으로 확인하는 것(CI)과 "자동으로 내보내는 것"(CD)의 차이, 그리고 CD에 필요한 권한(SSH 키, 네트워크)

## 진행 순서 (안)
1. 저장소 생성 + 3주차 코드 복사, 테스트 통과 확인
2. **CI 먼저:** 테스트용 작은 CSV + GitHub Actions(pytest) → push해서 초록불 확인. 화면 테스트가 건너뛰지 않고 도는지 로그로 확인
3. `Dockerfile` + `.dockerignore` — `.env`, `data/`, `.venv/`가 이미지에 들어가지 않는지 확인 → CI에 `docker build` 단계 추가
4. `compose.yaml` (api, ui, volume, env_file) → **로컬에서** 전체 흐름 확인 (업로드 → 질문 → 재시작 후 대화 유지)
5. AWS 준비: 결제 예산 알림, 키 페어, 보안 그룹(22·8501 내 IP만), OpenAI 사용 한도
6. EC2 생성 → SSH 접속 → Docker 설치 → `git clone` → `.env` 생성 → 예시 데이터 `scp`
7. `docker compose up -d --build` → 브라우저로 외부 접속 확인 → `docker compose logs`로 로그 확인
8. 재부팅해도 자동으로 다시 뜨는지, volume의 대화 기록이 남는지 확인
9. (여유) Nginx, HTTPS, CloudWatch 로그, CD 방법 비교
10. REPORT.md + 블로그 초안, 사용하지 않을 때 인스턴스 중지

CI를 Docker보다 먼저 두는 이유: 이후 Dockerfile·compose를 고칠 때마다 push하면 테스트와 빌드가 자동으로 확인된다.

## 시작 전에 준비할 것 (직접)
- [ ] **Docker Desktop 실행** — 설치(29.6)는 되어 있지만 지금은 꺼져 있다
- [ ] 4주차 GitHub 저장소 생성
- [ ] AWS 콘솔 로그인 확인, 리전(서울 `ap-northeast-2`) 결정, **예산 알림** 설정
- [ ] OpenAI 대시보드에서 **월 사용 한도** 설정
- AWS CLI는 설치되어 있지 않다. 이번 주는 웹 콘솔로 충분하다

## 위험과 대비
| 위험 | 대비 |
|---|---|
| API 키 노출 | `.dockerignore`·`.gitignore`로 제외, EC2에는 파일로만 두고 권한 제한 |
| 모르는 사람이 접속해 크레딧 사용 | 보안 그룹 IP 제한 + OpenAI 사용 한도 |
| EC2 비용이 계속 나감 | 예산 알림, 작업이 끝나면 인스턴스 중지 (종료하면 디스크 데이터도 사라짐) |
| 메모리 부족으로 빌드·실행 실패 | t3.small 또는 swap, `free -h`로 확인 |
| 컨테이너를 다시 만들 때 대화 기록 유실 | volume 확인 테스트를 진행 순서에 포함 (8번) |
| CI가 초록불인데 실제로는 테스트를 건너뜀 | 테스트용 데이터 준비, CI 로그에서 skip 수 확인 (`pytest -rs`) |
| CI 설정에 비밀 값이 새어 나감 | 테스트에 API 키가 필요 없게 유지. workflow에 `.env`를 만들지 않는다 |

## 완료 체크
- [ ] GitHub Actions CI: push마다 pytest + docker build (화면 테스트 포함)
- [ ] Dockerfile 작성 + 로컬 실행
- [ ] EC2 인스턴스 생성 + SSH 접속
- [ ] EC2에서 컨테이너 실행
- [ ] 외부에서 접속 확인
- [ ] (여유가 되면) Nginx, HTTPS, CloudWatch

## 블로그 주제
Docker + EC2로 AI 서비스 첫 배포하기 — "내 컴퓨터에서는 되는데"를 없애는 과정
