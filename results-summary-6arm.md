# 9-arm 오케스트레이션 벤치마크 — 종합 비교 (2026-08-02, arm7~arm9 추가 2026-08-03)

## 실험 동기

원래는 model=Sonnet + Claude Code 내장 advisor(fable) 조합으로 오케스트레이션을
운용하려 했으나, bash 실행 시 advisor 모드가 지속되지 않고 계속 끊기는
문제가 있었다. 우회책으로 **오케스트레이터=fable(Opus), executor=Sonnet**
구조로 전환했는데, 이번엔 다른 문제가 반복 관측됐다 — 토큰 소모가 크고,
fable이 사소한 사항까지 직접 처리해버리는 비효율이 계속 발생. 이 비효율의
원인이 정말 오케스트레이션 구조(fable 방식) 자체인지, 아니면 다른 요인
(모델 티어, advisor 지시 유무)인지 구분이 안 된 상태였다 — 이걸 확인하려고
6-arm 실험을 설계했다.

**실측 결과는 애초 문제의식과 반대 방향을 가리켰다.** 구조나 모델만 바꾼
arm1~5·arm7·arm8은 42개 태스크 중 위임을 거의 하지 않았다(0/42) — "직접
처리"가 비효율이 아니라 이번 태스크 규모 대비 합리적 선택이었다는 신호.
위임을 실제로 발생시킨 조건(arm6·arm9, 둘 다 advisor=on)에서는 오히려
해당 태스크(T2·T4) 소요시간이 다른 arm보다 더 길었다(arm6 T2 93s vs
40s대, arm9 T2 123s·T4 183s) — 위임 자체가 spawn 오버헤드로 이어짐을
보여준다. 즉 "fable이 직접 처리해서 비효율적이다"보다는 "작은 태스크에
억지로 위임을 시키면 오히려 오버헤드가 는다"는 결론에 가깝다. 다만 이번
태스크셋이 트리비얼~중간 규모에 한정돼 있어, 더 큰 프로덕션 규모 작업에도
이 결론이 그대로 적용되는지는 미검증이다.

**원래 문제(오케스트레이터=fable + 우회 구성에서 토큰 낭비)를 직접
재현·대조한 것이 arm8→arm9 페어다.** arm8(구조=orch, 모델=fable,
advisor=off)은 원래 사용자가 실사용하던 우회 구성을 그대로 재현 —
결과는 역시 위임 0/6, 원래 문제의식이었던 "비효율"이 이 조건 자체의
결함이 아니라 advisor 지시 부재의 결과임을 다시 확인했다. arm9는
동일 하네스에 advisor=on만 추가한 짝 — 위임이 2/6으로 늘어 arm6(sonnet+
advisor=on, 1/6)보다 높은 위임 성향을 보였다. "advisor 지시만이 위임을
유발한다"는 6-arm 결론이 fable에서도 유지되며, 모델 티어가 advisor
반응성 자체에도 영향을 준다는 새 신호가 나왔다(N=1, 확정적 결론 아님).
**session-report 재집계 결과, 위임이 실제 발생했을 때(arm9) subagent
토큰이 arm6의 약 4.1배(1,458,380 vs 356,325)** — 원래 문제의식이었던
"fable 우회 구성이 토큰을 많이 먹는다"가, 위임이 안 일어나는 조건(arm8)
에서는 재현 안 되고 위임이 실제로 일어나는 조건(arm9)에서만, 그것도
sonnet보다 더 크게 나타남. 즉 문제는 "fable이 직접 처리해서"가 아니라
"fable이 위임할 때 sonnet보다 더 비싸게 위임한다"였을 가능성.

## 요약

팩터 분리 재설계(`docs/reinforcement-plan.md`) 이후 첫 실행. 구 4-arm은
model/advisor/구조가 동시에 바뀌는 confound였음 — 이번엔 3축(구조/모델/advisor)을
각각 독립 2셀(baseline vs treatment)로 분리, 교차 매트릭스 없음.
baseline(구조=single, 모델=sonnet, advisor=off) 조건이 arm1/arm3/arm5에서
3회 독립 반복 — 세션 간 노이즈 추정용이며 어느 한 대조(contrast)의 N=3은 아니다.

## arm 정의

| arm | 구조 | 모델 | advisor(ORCH_RULE) |
|---|---|---|---|
| arm1-struct-single-base | single | sonnet | off (baseline) |
| arm2-struct-orch | orch(오케스트레이터+executor 위임 가능, 지시 없음·자율판단) | sonnet | off |
| arm3-model-sonnet-base | single | sonnet | off (baseline 반복) |
| arm4-model-opus | single | opus | off |
| arm5-advisor-off-base | single | sonnet | off (baseline 반복) |
| arm6-advisor-on | single | sonnet | **on** |
| arm7-orch-opus | orch(arm2와 동일 하네스) | opus | off |
| arm8-orch-fable | orch(arm2·arm7과 동일 하네스) | fable | off |
| arm9-orch-fable-advisoron | orch(arm8과 동일 하네스) | fable | **on** |

**arm7·arm8은 팩터 분리 축 밖의 결합 조건**(`docs/reinforcement-plan.md`
(b) 항목) — 6-arm은 구조축·모델축을 의도적으로 교차 안 시켰는데, 사용자가
실제로 쓰던 우회 구성(오케스트레이터=Opus 또는 Fable + executor=Sonnet,
즉 arm2·arm4 조건을 동시에 켠 상태)을 재현한 arm이 없었음. arm2·arm4
개별 효과가 결합 시에도 유지되는지(비선형/상호작용 효과) 검증하려고
2026-08-03 arm7(opus) 추가 실행, 이어서 opus를 fable로 바꾼 arm8을
추가해 "원래 실사용하던 구성" 자체를 더 정확히 재현.

**arm9은 arm8의 advisor=on 짝**(결합 축 밖, arm8과 반드시 페어로 비교) —
arm8만으로는 "advisor=off일 때 문제가 재현되는지"만 보이고 "advisor
룰을 얹으면 해소되는지"는 알 수 없어서, arm8과 동일 하네스에 ORCH_RULE=on만
추가해 2026-08-03 같은 날 추가 실행.

태스크셋: T1(트리비얼) → T2(소규모 멀티파일) → T3(판단+글쓰기) → T4(bash
스트레스) → T5a/T5b(위임 임계점 탐색, 편집량 고정·참조 파일 수만 0→2→4로 증가).

## 핵심 결과: 위임은 advisor 지시문에서만 발생

| arm | T1 | T2 | T3 | T4 | T5a | T5b | 위임 발생 |
|---|---|---|---|---|---|---|---|
| arm1-struct-single-base | 직접 | 직접 | 직접 | 직접 | 직접 | 직접 | 0/6 |
| arm2-struct-orch | 직접 | 직접 | 직접 | 직접 | 직접 | 직접 | 0/6 |
| arm3-model-sonnet-base | 직접 | 직접 | 직접 | 직접 | 직접 | 직접 | 0/6 |
| arm4-model-opus | 직접 | 직접 | 직접 | 직접 | 직접 | 직접 | 0/6 |
| arm5-advisor-off-base | 직접 | 직접 | 직접 | 직접 | 직접 | 직접 | 0/6 |
| arm6-advisor-on | 직접 | **위임(1회)** | 직접 | 직접 | 직접 | 직접 | 1/6 |
| arm7-orch-opus | 직접 | 직접 | 직접 | 직접 | 직접 | 직접 | 0/6 |
| arm8-orch-fable | 직접 | 직접 | 직접 | 직접 | 직접 | 직접 | 0/6 |
| arm9-orch-fable-advisoron | 직접 | **위임(1회)** | 직접 | **위임(1회)** | 직접 | 직접 | 2/6 |

54개 태스크 실행 중 위임은 **arm6 T2(1건), arm9 T2·T4(2건)** 뿐. 구조축
(arm2·arm7·arm8, 오케스트레이터+executor 위임이 하네스 수준에서 가능한
조건)도, 모델축(arm4 Opus, arm8·arm9 Fable)도 자율적으로는 위임을 유발하지
않음 — **ORCH_RULE 텍스트 지시(advisor=on)만이 위임을 실제로 발생시킴**.
arm2의 T2 로그(사례집 기록): "orch 구조라 해도 위임 지시 부재 + 파일 수
한 자릿수 + 동일 패턴 반복 조건이면 오케스트레이터 역할의 세션도 직접
처리를 선택한다 — 구조축 자체보다 태스크 판단 복잡도가 위임 여부를 더
강하게 결정한다."

**arm7(구조=orch + 모델=opus 결합)·arm8(구조=orch + 모델=fable 결합) 둘 다
0/6** — arm2·arm4 각각의 "위임 안 함"이 결합 조건에서도 그대로 유지됨,
상호작용 효과 없음. 즉 "구조축·모델축은 개별로도 위임을 안 만들고, 둘을
합쳐도(오케스트레이터 모델을 opus든 fable이든) 안 만든다"로 일반화 가능.
원래 문제의식이었던 "오케스트레이터=fable 우회 구성에서 사소한 것까지
직접 처리"하던 현상이 arm8에서 정확히 재현됐고, 이번 결과로는 그게 구조·
모델 결합의 부작용이 아니라 advisor 지시 부재의 결과로 재해석됨.

**arm9(arm8+advisor=on)에서 위임 2/6로 증가** — arm6(sonnet+advisor=on,
1/6)보다 높은 위임 성향. advisor 지시가 위임을 유발한다는 결론이 fable
오케스트레이터에서도 유지되며, 오히려 더 잘 반응한다는 신호(N=1, 확정
아님). arm9 T4(스크립트 구현+검증)까지 위임이 번진 것은 arm6에서는
관측되지 않았던 범위 확장 — advisor 룰 + fable 조합이 "판단 복잡도가
높은 태스크"의 위임 임계값을 더 낮췄을 가능성.

## T5a/T5b: 위임 임계점 탐색 결과

편집량은 T1과 동일(1줄 고정), 참조해야 하는 파일 수만 0(T1) → 2(T5a) →
4(T5b)로 늘림 — 9개 arm 전 구간에서 위임 전환 없음(arm9도 advisor=on인데
T5a/T5b는 직접 처리). 이번 태스크 규모(편집 1줄 고정)에서는 참조 파일 수
증가만으로는 위임 임계점에 도달하지 않는다 — 구 arm3가 제기한 가설("위임
기준은 파일 수가 아니라 읽어야 하는 파일 범위")은 이번 조건에서 지지되지
않음. 편집량 자체를 늘리는 후속 실험 필요.

**측정 한계가 arm8·arm9에서 공통 재확인됨**: 두 arm 모두 T2에서 참조
파일(README, rule-a/b/c)을 이미 읽어 T5a/T5b의 "읽기 범위 증가" 조작이
사실상 무력화(신규 Read 0)됐다고 각 로그가 자체 명시. arm7 로그(README만
선행 로드)에서도 같은 현상이 관측됐던 것과 동일 계열 — T5 티어로 임계점
신호를 얻으려면 T1~T4 없이 T5만 신선한 세션에서 단독 실행해야 함. 이번
9-arm 전 구간에 걸쳐 반복 관측된 설계 결함이라 다음 회차에는 필수 보정
사항으로 격상.

## 소요시간·툴콜·diff 규모

| arm | task | elapsed_sec | toolcalls | files_changed | insertions | deletions | errors |
|---|---|---|---|---|---|---|---|
| arm1 | T1 | 16 | 3 | 1 | 1 | 0 | 0 |
| arm2 | T1 | 30 | 4 | 1 | 1 | 0 | 0 |
| arm3 | T1 | 30 | 4 | 1 | 1 | 0 | 0 |
| arm4 | T1 | 35 | 6 | 1 | 1 | 0 | 0 |
| arm5 | T1 | 37 | 6 | 1 | 1 | 0 | 0 |
| arm6 | T1 | 15 | 5 | 1 | 1 | 0 | 0 |
| arm1 | T2 | 41 | 9 | 4 | 4 | 0 | 0 |
| arm2 | T2 | 40 | 7 | 4 | 5 | 1 | 0 |
| arm3 | T2 | 28 | 10 | 4 | 5 | 1 | 0 |
| arm4 | T2 | 31 | 8 | 4 | 6 | 1 | 0 |
| arm5 | T2 | 32 | 11 | 4 | 4 | 0 | 0 |
| arm6 | T2 | 93 | 6 | 4 | 4 | 0 | 0 (위임 1회, spawn 오버헤드 포함) |
| arm1 | T3 | 38 | 2 | 1 | 8 | 0 | 0 |
| arm2 | T3 | 35 | 3 | 1 | 8 | 0 | 0 |
| arm3 | T3 | 18 | 4 | 1 | 8 | 0 | 0 |
| arm4 | T3 | 56 | 6 | 1 | 8 | 0 | 0 |
| arm5 | T3 | 24 | 6 | 1 | 8 | 0 | 0 |
| arm6 | T3 | 24 | 4 | 1 | 7 | 0 | 0 |
| arm1 | T4 | 96 | 8 | 1 | 26 | 4 | 0 |
| arm2 | T4 | 90 | 11 | 1 | 18 | 0 | 1* |
| arm3 | T4 | 91 | 14 | 1 | 23 | 2 | 0 |
| arm4 | T4 | **1062** | 14 | 1 | 29 | 2 | 2* |
| arm5 | T4 | 92 | 16 | 1 | 35 | 5 | 0 |
| arm6 | T4 | **1330** | 12 | 1 | 16 | 0 | 0 |
| arm1 | T5a | 22 | 4 | 1 | 1 | 0 | 0 |
| arm2 | T5a | 20 | 4 | 1 | 1 | 0 | 0 |
| arm3 | T5a | 11 | 4 | 1 | 1 | 0 | 0 |
| arm4 | T5a | 38 | 4 | 1 | 1 | 0 | 0 |
| arm5 | T5a | 19 | 7 | 1 | 1 | 0 | 0 |
| arm6 | T5a | 18 | 5 | 1 | 1 | 0 | 0 |
| arm1 | T5b | 19 | 4 | 1 | 1 | 0 | 0 |
| arm2 | T5b | 19 | 4 | 1 | 1 | 0 | 0 |
| arm3 | T5b | 11 | 4 | 1 | 1 | 0 | 0 |
| arm4 | T5b | 23 | 4 | 1 | 1 | 0 | 0 |
| arm5 | T5b | 14 | 6 | 1 | 1 | 0 | 0 |
| arm6 | T5b | 14 | 5 | 1 | 1 | 0 | 0 |
| arm7 | T1 | 35 | 6 | 1 | 1 | 0 | 0 |
| arm7 | T2 | 40 | 9 | 4 | 5 | 1 | 0 |
| arm7 | T3 | 60 | 4 | 1 | 7 | 0 | 0 |
| arm7 | T4 | 150 | 11 | 1 | 59 | 8 | 0 |
| arm7 | T5a | 35 | 3 | 1 | 1 | 0 | 0 |
| arm7 | T5b | 40 | 4 | 1 | 1 | 0 | 0 |
| arm8 | T1 | 20 | 3 | 1 | 1 | 0 | 0 |
| arm8 | T2 | 32 | 9 | 4 | 5 | 1 | 0 |
| arm8 | T3 | 29 | 2 | 1 | 8 | 0 | 0 |
| arm8 | T4 | 79 | 9 | 1 | 33 | 4 | 0 |
| arm8 | T5a | 18 | 2 | 1 | 1 | 0 | 0 |
| arm8 | T5b | 15 | 2 | 1 | 1 | 0 | 0 |
| arm9 | T1 | 16 | 5 | 1 | 1 | 0 | 0 |
| arm9 | T2 | 123 | 15 | 4 | 5 | 1 | 0 (위임 1회, spawn 오버헤드 포함) |
| arm9 | T3 | 40 | 3 | 1 | 7 | 0 | 0 |
| arm9 | T4 | 183 | 22 | 1 | 32 | 2 | 0 (위임 1회, executor 실작업 131s 포함) |
| arm9 | T5a | 35 | 4 | 1 | 1 | 0 | 0 |
| arm9 | T5b | 45 | 4 | 1 | 1 | 0 | 0 |

\* errors는 스크립트 결함이 아니라 세이프가드 정상 발동/자체 오편집
즉시복구로 확인됨(각 arm 로그 각주 참조) — "bash 거부·권한 프롬프트·hook
차단" 의미의 에러는 9개 arm 전 구간 0건.

**baseline 3반복(arm1/arm3/arm5) 노이즈**: 같은 조건인데도 T2 elapsed가
41/28/32s로 갈리지만 자릿수는 일관 — baseline 자체는 안정적. T4에서
arm1(96s)만 diff가 유독 큼(26/4) — 나머지 baseline 두 arm(91s/23·2,
92s/35·5)과 비교해도 특이점은 아님.

**T4 시간축 이상치**: arm4(1062s), arm6(1330s)이 나머지(90~96s)보다 10배
이상 큼. 둘 다 diff 규모(29·16)와 toolcalls(14·12)는 다른 arm과 같은
자릿수 — 실작업량이 아니라 벽시계 지연(모델 응답 대기, 턴 경계)이 지배적
원인으로 각 arm 로그에 자체 명시됨. 위임 유무(둘 다 0)로도 설명 안 됨 —
모델축·advisor축 해석 시 elapsed_sec보다 diff·toolcalls 축을 우선 참고할 것.
arm7 T4(150s)는 arm1~5의 90~96s대보다는 다소 크지만 arm4/arm6의 이상치
(1000s대)와는 자릿수가 다름 — diff 규모(+59/-8)도 arm7 시점 기준 가장 커서,
스크립트에 `--dry-run` 옵션을 추가하는 실제 구현 작업이 반영된 결과로
해석됨(다른 arm의 T4 구현 범위와 정확히 동일하진 않을 수 있음, 개별 로그 참조).

arm7 T5a·T5b(3·4 toolcalls)는 arm1~6 중 가장 적은 축에 속함 — README가
이전 태스크(T2)에서 이미 컨텍스트에 올라와 T5a에서 재읽기가 생략된 것으로
보임(로그 자체 명시, "측정 한계" 항목). T5a·T5b의 toolcalls 3 vs 4를
그대로 "참조 파일 2개 vs 4개" 효과로 해석하면 안 됨.

**arm8·arm9 T4는 다시 정상 자릿수(79s·183s)로 복귀** — arm4/arm6의
1000s대 이상치가 fable에서는 재현되지 않음. arm9 T4(183s)는 위임 1회
포함(executor 실작업 131s)이라 arm8(79s, 직접)보다 긴 것이 예상된
spawn 오버헤드 — 이상치가 아니라 위임 비용으로 설명 가능한 정상 범위.
arm9 T2(123s)도 마찬가지로 arm6 T2(93s)보다 긴데, 둘 다 위임 1회 포함
조건이라 "fable+advisor=on의 위임 spawn 비용이 sonnet+advisor=on보다
크다"는 가설과 일치 — N=1이라 확정은 아니나 arm6/arm9만 놓고 보면 방향은
일관됨.

## 토큰·캐시 축 (session-report 복구, 2026-08-02 24h 스코프)

`session-report:session-report` 스킬로 각 arm worktree를 별도 프로젝트로
분리 집계. worktree 경로 자체가 프로젝트 키로 잡혀 arm별 매핑이 정확함.

| arm | api_calls | input tokens | cache 적중률 | output tokens | subagent 호출 | subagent tokens |
|---|---|---|---|---|---|---|
| arm1-struct-single-base | 55 | 6,119,809 | 92.5% | 16,203 | 0 | 0 |
| arm2-struct-orch | 54 | 4,751,944 | 92.6% | 18,606 | 0 | 0 |
| arm3-model-sonnet-base | 72 | 7,542,374 | 93.0% | 19,345 | 0 | 0 |
| arm4-model-opus | 60 | 5,750,686 | 91.7% | 26,668 | 0 | 0 |
| arm5-advisor-off-base | 82 | 8,170,788 | 94.9% | 22,828 | 0 | 0 |
| arm6-advisor-on | 77 | 7,431,294 | 93.1% | 20,243 | **1** | **356,325** |
| arm7-orch-opus | 50 | 3,783,250 | 92.1% | 30,833 | 0 | 0 |
| arm8-orch-fable | 38 | 2,518,341 | 97.5% | 19,844 | 0 | 0 |
| arm9-orch-fable-advisoron | 54 | 3,182,551 | 93.6% | 23,631 | **2** | **1,458,380** |

**위임 발생 arm(6·9)만 subagent 토큰이 잡힘** — arm6(356,325, 위임 1회)·
arm9(**1,458,380**, 위임 2회). 위임하지 않은 나머지 7개 arm은 전부
subagent_calls=0으로 명확히 대조 — "위임은 advisor 지시문에서만 발생한다"는
delegations 필드 관측과 토큰 데이터가 서로 독립적인 경로로 일치함(교차 검증).

**arm9의 subagent 토큰이 arm6의 약 4.1배** — 위임 횟수는 2배(2 vs 1)인데
토큰은 4배 넘게 증가, 회당 평균(arm9 729,190 vs arm6 356,325)도 2배 이상
차이남. fable 오케스트레이터가 spawn하는 executor 위임 1건당 소모하는
토큰이 sonnet 오케스트레이터보다 유의미하게 큼 — **원래 문제의식("fable
우회 구성이 토큰을 많이 먹는다")이 위임이 실제로 발생하는 조건(advisor=on)
에서는 정량적으로 확인됨.** 단 arm9 T4는 executor 실작업이 131초로 길어
(다른 위임보다 큰 태스크였음) 위임 1건당 비용이 태스크 크기에 크게
좌우될 수 있음 — "fable executor spawn이 본질적으로 더 비싸다"와 "이번
arm9의 위임 태스크가 우연히 더 컸다"를 구분하려면 동일 태스크 크기에서
sonnet vs fable executor spawn 비용만 격리하는 후속 실험이 필요하다.

cache 적중률은 전 arm 91.7~97.5%로 큰 차이 없음 — model(opus/sonnet/fable)이나
구조(single/orch) 차이가 캐시 효율에 유의미한 영향을 주지 않음. arm8이
가장 높음(97.5%)이나 baseline 반복(arm1 92.5%, arm3 93.0%)과 비교해도
노이즈 범위로 판단.

output tokens는 arm4(opus, 26,668)·arm7(opus, 30,833)이 가장 높음 — 다른
sonnet/fable arm들(16k~24k) 대비 완만하게 큼. Opus가 더 장문으로 응답하는
경향과 일치하나 arm4/arm7 2개 관측치뿐이라 확정적 결론은 아님. fable
(arm8 19,844·arm9 23,631)은 sonnet 계열과 비슷한 범위.

## 부수 발견: claude-smart 전역 훅을 매개로 한 세션 간 정보 유출

arm6 T2 위임 기록(delegations=1)에 대해 오케스트레이터·arm6 세션 양쪽에
소급 정정을 유도하는 규칙이 반복 주입됨. `~/.reflexio/data/reflexio.db`
직접 조회로 확인: 프롬프트 인젝션이 아니라 claude-smart 플러그인이 이
벤치마크 대화 자체를 실시간 관찰·학습해 재주입하는 설계된 동작
(2026-08-02 08:04~12:34 사이 38개 규칙 실시간 생성, 사전 학습분
agent_playbooks는 0건). 전역 플러그인이 세션 격리 전제를 우회하는 정보
유출 경로가 될 수 있음이 실증됨 — 상세는 `docs/reinforcement-plan.md`
"부수 발견" 절 참조. arm1~6 전 구간이 동일 조건에서 실행됐으므로 arm 간
상대 비교는 유효하나, 각 arm이 "완전히 독립된 관측"이라는 전제는
성립하지 않는다.

**arm7에서 추가 확인된 오염 경로: context-mode 등 전역 PreToolUse 훅이
매 Bash/Read 호출마다 가이드 텍스트를 주입.** 위임(delegations)·툴콜
(toolcalls)·에러(errors) 세 필드 어디에도 안 잡히는 오염이라 jsonl 스키마로는
발견 불가 — arm7 T3 로그에서 사례로 기록됨. 전역 훅이라 모든 arm에 동일하게
걸리므로 arm 간 상대 비교 자체는 여전히 유효하지만, "구조축·모델축·advisor축
외 요인은 없다"는 결론에는 "전역 훅이 켜진 환경에서"라는 단서가 필요함.
후속 조치 후보: jsonl에 `hook_injections` 필드 추가, 또는 DISABLE_OMC/
OMC_SKIP_HOOKS로 훅을 끈 별도 셀 확보해 오염분 차감.

## 미해결/후속 과제

- ~~계획서 3번(session-report로 토큰/캐시 수치 복구)~~ — 완료, 위 "토큰·캐시 축" 절 참조.
- T5a/T5b가 이번 편집량(1줄 고정)에서는 위임 전환점을 못 찾음 — 편집량
  자체를 늘리는 T6 티어 설계 필요(범위 밖, 후속 검토).
- arm4/arm6 T4의 벽시계 지연 원인 미규명(외부 요인 추정, 재현 조건
  불명) — N≥3 반복 시 재관측되는지 확인 필요.
- arm8·arm9 worktree 완료 후 uncommitted 상태로 남아있음 — teardown 실행
  전 diff export 확인 필요(`bench-teardown.sh`가 자동 강제).
- arm7 완료(2026-08-03) — `docs/reinforcement-plan.md` (b) 항목 종료.
  diff export는 `~/workspace/.bench/results/arm7-orch-opus.{diff,stat,log,jsonl}`에
  보존, worktree는 teardown됨.
- arm8·arm9 완료(2026-08-03) — 원래 실사용 구성(오케스트레이터=fable)을
  opus 대신 fable로 정확히 재현(arm8)하고 advisor=on 짝(arm9)까지 실행,
  "advisor 지시만이 위임을 유발한다"는 결론이 fable에서도 유지됨을 확인.
  아직 teardown 안 함 — 두 worktree 모두 diff export 대기 중.
- (a) 항목(내장 advisor=fable 버그 재현)은 Claude Code UI 상 Fable 5
  advisor가 "temporarily unavailable"로 표시돼 실행 불가했던 건이었으나,
  이후 세션에서 메인 세션 모델 자체를 Fable로 쓰는 우회 경로(arm8·arm9)로
  대체 진행됨 — advisor 슬롯의 Fable 가용성 자체는 여전히 미확인 상태로
  남아있으나 실험 목적 달성에는 지장 없어 보류 유지.
- hook_injections 미계측 문제(위 "부수 발견" 절) — 다음 회차 벤치마크
  설계 시 로그 스키마에 반영 필요, 이번 9-arm 결과엔 소급 적용 안 함.
- T5 티어의 "선행 로드로 인한 무력화"가 arm7·arm8·arm9 3개 arm에서
  반복 관측됨(위 "T5a/T5b" 절) — 다음 회차엔 T5 단독 신선 세션 실행을
  필수 설계 요소로 반영할 것.
- ~~arm7·arm8·arm9 토큰·캐시 데이터 결측~~ — 완료(2026-08-03). teardown된
  worktree라도 세션 트랜스크립트는 `~/.claude/projects/`에 프로젝트 키로
  보존돼 session-report 재집계 가능함을 확인. 결과는 위 "토큰·캐시 축"
  절에 반영 — arm9 subagent 토큰이 arm6의 약 4.1배(1,458,380 vs 356,325)로
  원래 문제의식(fable 우회 구성의 토큰 낭비)이 위임 발생 조건에서 정량
  확인됨.
- arm4/arm6 T4 벽시계 지연(1000s대 이상치) 원인 미규명 — N≥3 반복 실행
  필요, 새 벤치 라운드로 별도 계획(이번 세션에서 착수 안 함, 사용자
  확인: "4는 별도 계획"으로 유예).
