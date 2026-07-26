---
name: delegate-agent-model
enabled: true
event: file
action: warn
tool_matcher: Agent
conditions:
  - field: model
    operator: regex_match
    pattern: ^(|opus)$
---

<!-- hookify conditions schema has no native "missing OR equals" operator; model 필드가 없으면
     빈 문자열로 취급되지 않을 수 있어 실제 게이팅은 delegation-reminder.py(MSG_AGENT_NO_MODEL/
     MSG_AGENT_OPUS)가 담당한다. 이 룰은 터미널 가시성용 보조 장치. -->

⚠️ **위임 원칙 점검** (서브에이전트라면 이 경고 무시하고 계속 진행)

메인 세션(Fable)이 Agent spawn 시 model을 명시하지 않았거나 opus를 선택함.

**원칙:** 위임 기본값은 sonnet.
- model 미지정 → sonnet 명시할 것.
- model=opus → 아키텍처 설계·고난도 구현 등 명확한 예외인지 확인, 아니면 sonnet으로 낮출 것.
- opus를 쓰는 경우 프롬프트에 사유를 한 줄 남길 것.
