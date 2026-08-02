# orchestration-bench

[github.com/alexxony/orchestration-bench](https://github.com/alexxony/orchestration-bench)

Claude Code 세션에서 model / advisor / 오케스트레이션 방식(단일 세션,
오케스트레이터-executor 분리, 자동화 루프 등)을 바꿔가며 동일한 태스크셋을
실행하고, 위임 판단·에러·결과물 품질을 비교하기 위한 벤치마크 하네스다.

## 구조

- `bench-setup.sh` — arm 4개(각각 별도 git worktree + 브랜치)를 생성한다.
  arm 이름/브랜치는 스크립트 상단 `ARMS` 배열에서 정의 — 원하는 만큼
  추가/수정 가능.
- `bench-tasks.md` — 각 arm에서 순서대로 실행할 태스크 T1~T4 정의.
  트리비얼 → 소규모 멀티파일 → 판단 필요 → bash 스트레스, 난이도 순.
- `bench-teardown.sh` — worktree 정리(결과 로그는 기본 보존).
- `sample-files/` — 태스크 대상이 되는 더미 파일들. 실제 프로덕션 코드가
  아니라 벤치마크 전용 샘플이다.

## 사용법

```bash
./bench-setup.sh
```

arm마다 별도 터미널을 열고(또는 순차로), 각 worktree 안에서
`bench-tasks.md`의 지시문을 그대로 세션에 던진다. 3축(구조/모델/advisor)을
각각 독립 2셀(baseline vs treatment)로 분리해서 비교한다 — 교차 매트릭스
아님, 팩터 분리 이유는 `docs/reinforcement-plan.md` 참조:

| arm | 구조 | 모델 | advisor(ORCH_RULE) |
|---|---|---|---|
| arm1-struct-single-base | single | sonnet | off (baseline) |
| arm2-struct-orch | orch(오케스트레이터+executor 위임 가능, 지시 없음) | sonnet | off |
| arm3-model-sonnet-base | single | sonnet | off (baseline 반복) |
| arm4-model-opus | single | opus | off |
| arm5-advisor-off-base | single | sonnet | off (baseline 반복) |
| arm6-advisor-on | single | sonnet | **on** |

각 태스크 완료 후 결과(소요시간/토큰/툴콜수/에러/diff품질)를
`~/workspace/.bench/results/<arm-name>.log`(자유서술) +
`<arm-name>.jsonl`(기계가독)에 기록한다. `bench-setup.sh`가 로그 템플릿을
자동 생성해준다.

전체 태스크 끝나면:

```bash
./bench-teardown.sh          # worktree 정리, 로그는 보존
./bench-teardown.sh --purge-results  # 로그까지 삭제
```

## 결과

- [`results-summary-6arm.md`](results-summary-6arm.md) — 6-arm 실행(T1~T5b)
  종합 비교. 핵심: 30개 태스크 중 위임은 arm6(advisor-on) T2 단 1건뿐 —
  구조축·모델축은 자율 위임을 유발하지 않고 advisor 텍스트 지시만이
  위임을 실제로 발생시킴. 토큰·캐시 축 포함.
- [`docs/reinforcement-plan.md`](docs/reinforcement-plan.md) — 구 4-arm
  confound 지적부터 6-arm 팩터 분리 설계 배경, claude-smart 전역 훅을
  매개로 한 세션 간 정보 유출 부수 발견까지.
- 구 4-arm 결과(참고용, confound 있음): [`results-summary.md`](results-summary.md)

## 관찰 포인트

- **위임 여부**: 같은 태스크를 던져도 model/advisor/구조에 따라 직접
  처리하는지 서브에이전트에 위임하는지가 달라진다. 위임이 "가능"한
  것과 "실제로 일어나는" 것은 다르다 — advisor가 켜져 있어도 호출
  안 될 수 있다.
- **에러축**: bash 거부, 권한 프롬프트, hook 차단 발생 여부.
- **diff 품질**: 결과물이 기존 스타일/형식을 얼마나 잘 따르는지, 판단이
  필요한 태스크(T3)에서 근거를 얼마나 구체적으로 드는지.

## 주의

- 태스크 순서 의존적이다(T3가 T1/T2 결과를 참조하는 경우가 많음) — 병렬
  N-에이전트 모드(예: team)로 태스크를 흩으면 이 의존성이 깨진다.
- 자기보고를 그대로 믿지 말 것 — 각 arm 완료 후 로그 파일과 실제
  `git diff --stat`을 오케스트레이터(사용자 세션)가 직접 대조해서
  검증하는 것을 권장한다.
