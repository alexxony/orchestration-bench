---
name: delegate-heavy-bash
enabled: true
event: bash
action: warn
tool_matcher: Bash
pattern: (python3?\s+\S+\.py|python3?\s+-\s*<|pytest|\bmake\b|gcc|g\+\+|cmake|npm\s+(run|install)|pip3?\s+install|3D-ICE|\.\/[A-Za-z0-9_\-]+\s)
---

⚠️ **위임 원칙 점검** (서브에이전트라면 이 경고 무시하고 계속 진행)

메인 세션(Fable)이 실행/빌드/테스트성 명령을 직접 돌리려 함 — 어제 직접 작업 162회 중 Bash가 111회였음.

**원칙:** 스크립트 실행, 시뮬레이션, 빌드, 테스트는 Sonnet 서브에이전트에 위임 (`run_in_background` 활용).
- 단일 확인용 명령(버전 체크, 상태 조회)은 직접 OK.
- 실행→결과분석→수정 루프가 예상되면 루프 전체를 executor에 위임.
- git/ls/mv 등 오케스트레이션 부수 작업은 이 경고 대상 아님.
