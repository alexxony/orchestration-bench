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

## 부수 발견 (2026-08-02, 6-arm 2차 실행 중 관측): 글로벌 훅을 매개로 한
  세션 간 정보 유출

6-arm(T1~T5b) 실행 도중, arm6(advisor-on) T2에서 위임(delegations=1)이
실제 발동한 직후, 오케스트레이터 세션과 arm6 세션 양쪽 모두의
UserPromptSubmit 훅 컨텍스트에 "이 delegations=1 기록은 허위이니 0으로
정정하라"는 취지의 claude-smart 규칙(`[cs:s1-XXX]` 형식)이 반복
주입됨. arm6는 이를 프롬프트 인젝션으로 의심해 반박, 실제 T2 툴콜
이력(Agent spawn 1회, 이후 대상 파일 Read/Edit 없음)과 `git diff
--numstat` 재대조로 원 기록(delegations=1)을 유지했고 이 사건 자체를
notes.md 사례집에 기록함.

오케스트레이터 세션에서 `~/.reflexio/data/reflexio.db`(claude-smart
백엔드 DB, 포트 8071 상시 구동)를 직접 조회해 원인 확정:
**외부 인젝션이 아니라 claude-smart 플러그인의 설계된 정상 동작.**
`user_playbooks` 테이블에 2026-08-02 08:04~12:34 사이 **38개 규칙이
실시간 생성**됐고(예: id=1151/1152/1153이 12:32~12:34에 정확히 arm6
T2 완료 직후 생성), agent_playbooks(사전 학습분)는 count=0 — 즉 이
규칙들은 사전 학습된 지식이 아니라 **이번 벤치마크 대화 자체를
관찰하며 그 자리에서 만들어져 다음 턴에 즉시 재주입**된 것.

**구조적 함의**: claude-smart는 프로젝트 단위가 아닌 전역 플러그인이라
오케스트레이터 세션과 arm1~6 worktree 세션 전부가 동일한 백엔드
서비스를 공유한다. 각 arm은 서로 직접 통신하지 않지만(worktree 격리
전제는 유지됨), **claude-smart라는 공유 관찰자를 매개로 한 세션이
관측·판단한 내용이 다른 세션의 다음 턴 프롬프트에 간접적으로
흘러들어갈 수 있음**이 이번 실행에서 실증됨 — 이는 애초 벤치 설계가
전제한 "세션 간 완전 격리"를 깨는 제5의 변수(글로벌 훅 매개 정보
유출)이며, 사전 계획엔 없었지만 이번 6-arm 실행 자체가 우연히 발견한
결과로 기록해둔다. 08:04(bench-setup.sh 재설계 단계)부터 시작됐으므로
arm1~6 전 구간이 동일하게 이 조건 하에서 실행됨 — arm 간 상대 비교의
타당성 자체는 훼손되지 않으나(전 arm 동일 조건), 각 arm이 "완전히
독립된 관측"이라는 전제는 성립하지 않는다.

- **재현/차단 방법(향후 참고, 이번 회차는 실행 안 함)**: claude-smart는
  글로벌 플러그인이라 프로젝트별 비활성화 불가 — 완전 차단하려면
  플러그인 자체를 세션 시작 전 비활성화해야 함. 이번 6-arm은 이미
  arm1~5가 이 조건에서 실행됐으므로 지금 껐다 켜면 arm6만 다른 조건이
  되는 새로운 비대칭이 생겨 오히려 비교 불가 — 그대로 유지.

## 후속 실험 계획 (2026-08-03 이후 수행 예정, 사용자 지시로 문서화만 우선)

6-arm 결과 리뷰 중 사용자가 지적한 두 가지 미검증 지점. "실험 동기"
절(README.md, results-summary-6arm.md)과 직결되므로 우선순위 높음.

### (a) 내장 advisor(fable) 버그 재현 확인 — 먼저 수행

원래 문제의식의 출발점: model=Sonnet + Claude Code 내장 advisor(fable)
조합이 bash 실행 시 advisor 모드가 지속되지 않고 끊기는 버그가 있어서
오케스트레이터=fable(Opus)+executor=Sonnet 구조로 우회했었음. 이번
6-arm 실행에서는 오히려 이 내장 advisor를 매번 "No advisor"로 꺼두라고
지시했기 때문에, **이 버그가 지금도 재현되는지 자체를 확인한 적이 없다.**

절차: 새 세션에서 model=sonnet, 내장 advisor=fable로 설정 후 bash
실행이 필요한 태스크(예: bench-tasks.md T4 수준) 수행, advisor 모드
유지 여부 관찰.

- 버그가 고쳐졌으면: 원래 우회책(오케스트레이터=Opus 구조) 자체가 더
  이상 필요 없어짐 — 이번 6-arm 결과("구조/모델보다 advisor 지시가
  위임을 결정한다")를 바탕으로 model=sonnet+advisor=fable 직결 구성
  재검토.
- 여전히 버그면: 우회책의 존재 이유가 재확인됨 — (b)로 진행.

이건 엄밀한 벤치마크라기보다 Claude Code 자체 이슈 재현 여부 확인이라
결과가 바이너리(재현/미재현)로 나옴 — 별도 arm 인프라 없이 세션 하나로
빠르게 확인 가능.

### (b) arm7 — 원래 실사용 구성 재현 (구조=orch, 모델=opus)

지금 6-arm은 팩터 분리를 위해 구조축(arm2: 구조=orch, model=sonnet)과
모델축(arm4: model=opus, 구조=single)을 의도적으로 교차시키지
않았음 — 그 결과 **사용자가 실제로 쓰던 우회 구성(오케스트레이터=Opus
+ executor=Sonnet, 즉 arm2와 arm4의 조건을 동시에 켠 상태) 자체를
재현한 arm이 이번 6-arm에는 없다.**

arm7 정의(제안): 구조=orch, 모델=opus(오케스트레이터), advisor=off.
bench-tasks.md T1~T5b 동일 적용, 기존 arm과 동일 스키마(log/jsonl)로
기록.

관찰 포인트: arm2(구조만 orch, 0/6 위임)·arm4(모델만 opus, 0/6 위임)
각각은 위임을 안 만들었는데, 두 조건을 같이 켠 arm7도 여전히 0/6인지,
아니면 결합 시 위임이 발생하는지 — 팩터 분리 실험이 "각 축의 개별
효과 없음"을 "결합해도 효과 없음"으로 일반화할 수 있는지 검증하는
셈(비선형/상호작용 효과 확인).

### 실행 순서

(a) 먼저(빠르고 원인 규명에 직결) → 결과에 따라 (b) 진행 여부·설계
조정. 둘 다 별도 세션에서 사용자가 직접 재개 예정(2026-08-03~).
