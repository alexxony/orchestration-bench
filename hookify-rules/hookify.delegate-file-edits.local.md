---
name: delegate-file-edits
enabled: true
event: file
action: warn
tool_matcher: Edit|Write|MultiEdit
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.(py|c|cpp|cc|h|hpp|js|ts|tsx|rs|go|sh|json|yaml|yml|toml|ini|stk|flp|tcl)$
---

⚠️ **위임 원칙 점검** (서브에이전트라면 이 경고 무시하고 계속 진행)

메인 세션(Fable)이 코드/설정 파일을 직접 편집하려 함.

**원칙:** Fable은 오케스트레이션·검증 전담. 구현은 Sonnet 서브에이전트 위임.
- 트리비얼(파일 1개 미만, 한 줄 수정)만 직접 허용.
- 그 이상이면 `Agent(subagent_type: "oh-my-claudecode:executor")` 또는 `general-purpose` + `model: sonnet`으로 위임.
- 편집이 2회 이상 이어질 작업이면 지금 즉시 위임으로 전환.
