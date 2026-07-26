# 벤치마크 태스크 셋 (2026-07-25)

4개 arm(터미널/세션)에 동일하게 순서대로 던진다. 각 태스크 완료 후
`~/workspace/.bench/results/<arm-name>.log` 에 기록: 소요시간 / 토큰 /
툴콜 수 / 에러(bash 거부·권한 프롬프트·hook 충돌 등) / 결과물 diff 품질.

전제: 각 세션은 `~/workspace/.bench/<arm-name>/` 안에서 열 것 (worktree,
`bench-setup.sh`로 생성). arm 간 파일 충돌 없음.

---

## T1 — 트리비얼 (기준선)

`docs/orchestration-cost-model.md`에 관측 항목 한 줄 추가.
(참고: 2026-07-25 세션에서 동일 파일에 이미 "세션 모델 Sonnet 전환 관측"
섹션 추가한 선례 있음 — 그 스타일 참고, 내용은 각 arm에서 새로 작성.)

지시문 예:
> "docs/orchestration-cost-model.md 미해결 섹션에, 이번 벤치마크(4-arm
> worktree 비교) 자체를 향후 실측 항목으로 한 줄 추가해줘."

관찰 포인트: 위임 여부 자체를 판단하는지, 위임한다면 오버헤드가 태스크
크기 대비 얼마나 나오는지.

---

## T2 — 소규모 멀티파일 (위임 임계값)

`hookify-rules/` 안 3개 `.local.md` 파일 전부에 공통 헤더 문구 한 줄씩
추가 + `README.md`에 "각 룰 파일 상단에 OOO 헤더 추가함" 반영.

지시문 예:
> "hookify-rules/*.local.md 3개 파일 전부 맨 위에 '<!-- 벤치마크
> 표시 2026-07-25 -->' 한 줄 추가하고, README.md 구조 설명 절에
> 그 사실 한 줄 반영해줘."

관찰 포인트: 위임 판단을 언제 내리는지(트리비얼과 중간 경계), 병렬
처리 여부.

---

## T3 — 실제 판단 필요 (품질 축)

`docs/verification-gates.md` 읽고, G1~G6 중 하나 골라 새 사례
(가상 또는 이번 벤치마크 세션 자체 관측)를 `docs/incident-casebook.md`에
한 항목으로 추가 제안 + 근거 문서화.

지시문 예:
> "docs/verification-gates.md 읽고, G1~G6 중 이번 벤치마크 작업
> (worktree 격리, 태스크 위임 판단)에서 실제로 관측 가능한 게이트
> 하나 골라서, incident-casebook.md에 새 사례 항목(분류+5요소 형식)
> 추가해줘."

관찰 포인트: 순수 편집이 아니라 "판단+글쓰기" 품질. 오케스트레이터
티어별 결과물 질 차이가 가장 크게 드러날 구간.

---

## T4 — bash/도구 스트레스 (에러축 전용)

`bench-setup.sh`에 `--dry-run` 옵션 추가(실제 worktree 생성 없이 계획만
출력) + 직접 실행해서 검증.

지시문 예:
> "bench-setup.sh에 --dry-run 옵션 추가해줘. 켜면 실제 git worktree
> add를 실행하지 않고 무엇을 할지(경로·브랜치명)만 출력. 추가 후
> 직접 실행해서 정상 동작 확인해줘."

관찰 포인트: bash 실행 자체가 막히는지(권한 프롬프트, hook 거부),
실행 후 검증까지 스스로 하는지.

---

## 실행 순서

T1 → T2 → T3 → T4 (비용 낮은 순). 중간에 특정 arm에서 심각한 에러
(무한 재시도, bash 완전 거부 등) 나오면 그 arm은 해당 태스크에서
중단하고 로그에 사유만 기록 후 다음 태스크로 넘어간다.

## 종료 후

전체 태스크 끝나면 `~/workspace/claude-delegation-policy/bench-teardown.sh`
로 worktree 정리 (결과 로그는 기본 보존).
