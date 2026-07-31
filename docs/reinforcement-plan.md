# 벤치 보강 계획 (2026-07-31)

## 배경

4-arm(T1~T4) 1차 실행 결과(`results-summary.md`)는 "arm3만 위임 발생,
나머지 0회"라는 관측을 냈지만, 그대로 다른 저장소에 근거로 올릴 만큼
충분하지 않다는 판단. 원본 worktree는 이미 teardown되어 diff 재현
불가 — 아래 계획은 재실행 전제로 설계·인프라부터 고친다.

## 핵심 결함 (advisor 지적)

arm1~arm3 설계가 **confound**됨 — model / advisor / 구조(단일세션 vs
오케스트레이터-executor) 3개 변수가 동시에 바뀜. 그 결과 "arm3만
위임했다"는 관측이 구조 때문인지 Opus 모델 때문인지 구분 불가능.
N을 늘려 재실행해도 같은 confound를 세 번 더 재는 것일 뿐 — 우선순위는
N 증가가 아니라 팩터 분리.

## 보강 순서

### 1. 팩터 분리 (최우선, 설계 단계)

한 번에 한 축만 바꾸는 arm 매트릭스로 재설계:

- **구조축**: 모델 고정(Sonnet) — 단일세션 vs 오케스트레이터+executor
- **모델축**: 구조 고정 — Sonnet vs Opus
- **advisor축**: 기존 `ORCH_RULE=on/off` 토글 그대로 재사용(이미 단일축)

### 2. 태스크셋 — 위임 임계점 탐색

기존 T1~T4는 "전부 위임 안 함"으로 수렴한 sub-threshold 대조군으로
유지. arm3가 도출한 가설 — 위임 기준은 **수정 파일 수가 아니라
오케스트레이터가 읽어야 하는 파일/컨텍스트 양** — 을 테스트하는 신규
티어 추가. 편집량은 고정하고 읽어야 할 범위만 늘려가며 위임 전환점을
찾는다. 위임이 항상 발생하거나 항상 안 발생하는 티어는 정보량 0 —
교차점 근방을 노려야 함.

### 3. 토큰 축 — 재실행 전 재분석 우선

`session-report` 스킬로 기존 4개 arm 세션 transcript에서 토큰/캐시
수치 복구 가능한지 먼저 확인. 가능하면 재실행 없이 이 갭 해소.

### 4. 로그 인프라 — 재실행 전 반드시 완료

1차 실행의 근본 문제: arm 산출물이 별도 worktree에만 uncommitted로
존재 → teardown 시 diff 원본 소실, `results-summary.md` 손서술만 남음.
재발 방지책:

- **teardown 전 diff export 강제**: `bench-teardown.sh`에 사전 단계로
  각 arm worktree의 `git diff` / `git diff --stat`을
  `results/arm<N>.diff` / `results/arm<N>.stat`로 export → bench repo에
  커밋 → 그 다음에만 `git worktree remove` 허용.
- **로그 포맷 이원화**:
  - 기계가독: `results/<arm>.jsonl` — 태스크당 1줄(arm, task,
    elapsed_sec, toolcalls, delegations, errors, files_changed,
    insertions, deletions)
  - 자유서술: 기존 `.log` 유지(판단 근거·정성 관찰용)
- **메타데이터 생성 시점 고정**: `bench-setup.sh`가 로그 템플릿 만들
  때 model/advisor/ORCH_RULE/구조를 미리 채워 넣음 — 세션 중
  재구성(대화 기록에서 역추적) 금지.
- **종합 리포트 스크립트화**: `results-summary.md`처럼 손대조 대신,
  jsonl 여러 개 읽어 표로 뽑는 `results/compare.sh`(또는 `.py`) 작성 —
  재실행마다 수동 대조 반복 안 하도록.

### 5. N≥3 반복

1·2·4가 끝난 뒤에만 진행. 팩터 분리 안 된 상태에서 반복 늘리는 건
같은 confound를 여러 번 재는 것 — 순서 뒤집지 말 것.

## 실행 순서 요약

1(설계) → 2(태스크) → 4(로그 인프라, 재실행 전 완료) → 재실행(N=1로
팩터별 신호 확인 후 N≥3) → 3(토큰, 병행 가능).

## 미해결 (이번 보강 범위 밖)

- 1차 실행 arm1 diff 35줄 vs 나머지 68~79줄 차이 원인 — worktree
  소실로 영구 미검증.
