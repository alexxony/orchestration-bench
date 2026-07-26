# 4-arm 오케스트레이션 벤치마크 — 종합 비교 (2026-07-26)

## arm 정의

| arm | model | advisor | orchestration | ORCH_RULE |
|---|---|---|---|---|
| arm1 | Sonnet 5 | 활성(opus5), 실호출 0회 | 단일 세션(오케스트레이터=executor) | on |
| arm2 | Opus 5 단독 | 비활성 | 단일 세션(오케스트레이터=executor) | off |
| arm3 | Opus 5 (오케스트레이터) | 없음 | Opus 오케스트레이터 + Sonnet executor 위임(구 fable 체제) | on |
| arm4 | 기본값(sonnet 자동) | 기본 상태, 실호출 0회 | ultrawork 자동화 루프 | off |

## 위임 패턴

| arm | T1 | T2 | T3 | T4 |
|---|---|---|---|---|
| arm1 | 직접 | 직접 | 직접 | 직접 |
| arm2 | 직접 | 직접 | 직접 | 직접 |
| arm3 | 직접 | **위임**(sonnet 1회) | **분할**(판단=opus, 삽입=sonnet) | **위임**(구현=sonnet, 검증=opus 직접) |
| arm4 | 직접 | 직접 | 직접 | 직접 |

**핵심 관측**: 4개 arm 중 위임이 실제로 발생한 건 arm3뿐. arm1(advisor 있음)·arm2(opus 단독)·arm4(ultrawork)는 전부 위임 0회 — 이번 태스크셋(T1~T4) 규모가 spawn 오버헤드를 넘지 못한다는 공통 결론에 세 arm이 독립적으로 도달함. arm3만 오케스트레이터/executor 역할이 애초에 분리된 세션 구조라 위임이 구조적으로 강제됨.

## diff 규모

| arm | files changed | insertions | deletions |
|---|---|---|---|
| arm1 | 8 | 35 | 2 |
| arm2 | 8 | 76 | 7 |
| arm3 | 7 | 68 | 8 |
| arm4 | 8 | 79 | 9 |

arm1이 눈에 띄게 작음(35줄) — 나머지 세 arm(68~79줄)은 비슷한 규모. arm1만 유독 작은 이유는 로그상 T3에서 "가상 사례 대신 최소한만" 쓴 판단 차이로 보이나, 정확한 원인은 각 arm의 incident-casebook.md 삽입 줄 수 세부 비교 필요(미검증).

## 에러축

전 arm 공통: bash 거부 0 / 권한 프롬프트 0 / hook 차단 0. hook은 4개 arm 전부 안내(advisory) 수준으로만 작동, 실행을 막은 사례 없음.

T4(bash 스트레스)에서 arm별로 겪은 실행 이슈:
- arm1: Bash 툴 cwd가 매 호출 세션 시작 디렉토리로 리셋되는 이슈 — 상대경로 실행 불안정, 절대경로로 우회
- arm2: 이슈 없음
- arm3: dry-run이 기존 4-arm 전부 skip이라 핵심 분기 미실행 → 임시 5번째 arm 주입으로 강제 재현(공통 패턴, 아래 참조)
- arm4: 이슈 없음, 미커밋 상태에서 대화형 read 프롬프트 우회 확인

## 공통 관측: T4 dry-run 커버리지 갭

arm1·arm2·arm3·arm4 전부 독립적으로 동일한 문제를 발견: 기존 4개 arm이 이미 존재해 `--dry-run`이 항상 skip 분기로만 빠지고, 실제 `git worktree add` 출력 경로가 한 번도 실행되지 않음. 4개 세션 모두 각자 임시/가짜 arm을 추가해 미존재 경로를 강제 실행시켜 검증 — 서로 다른 model/orchestration 구조에서 동일한 사각지대를 동일한 방법으로 잡아낸 셈. 이 자체가 "검증 시 실제 미실행 분기를 찾아 강제 실행해야 한다"는 원칙(G3/G5 계열)의 교차 재현 사례.

## 각 arm이 도출한 문서 사례(C8)

4개 arm 전부 `docs/incident-casebook.md`에 C8을 각자 다르게 작성(원본 repo에 merge 안 됨, 각 worktree 로컬 diff로만 존재):
- arm1: G5(위임·통신 게이트) — 디스크 우선 확인 원칙
- arm2: G1(주장→문서 유입 게이트) — 벤치 로그 자체의 자기보고 한계
- arm3: G5(위임·통신 게이트) — 위임 임계값은 파일 수가 아니라 오케스트레이터가 읽어야 하는 파일 수
- arm4: G3(판정·폐기 결정 게이트) — frontmatter 파손 위험 자체 검증 사례

게이트 선택이 4개 다 다름 — 같은 태스크(T3)를 던져도 세션마다 "무엇이 이번 세션에서 실제로 관측 가능한 사건인가"를 다르게 해석. G5(위임/통신)가 2회(arm1, arm3), G1·G3가 각 1회.

## 미해결/후속 과제

- diff 규모 차이(arm1만 작음) 원인 미검증 — 파일별 세부 diff 대조 필요
- 토큰 소비량 전 arm 미계측(세션 리포트 별도 확인 필요) — 소요시간·툴콜수만 대리 지표로 사용됨
- 4개 arm 모두 uncommitted 상태로 남아있음 — teardown 시 worktree 통째 폐기 예정, 이 비교 리포트가 유일한 영구 기록
