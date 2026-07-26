# claude-delegation-policy

## 목적

Claude Code 세션에서 "Fable(메인 세션)은 오케스트레이션·검증 전담, 구현은 Sonnet 서브에이전트 위임" 원칙을 훅 기반으로 강제하기 위한 자산 모음이다. 특정 프로젝트에 종속되지 않는 독립 저장소로 분리해, 여러 프로젝트(Obsidian vault, Compiler_Thermal, compiler_thermal, hbm_build, gpu_solver_test 등)에서 동일한 정책을 공유한다.

## 문서 (`docs/`)

- [orchestration-cost-model.md](docs/orchestration-cost-model.md) — 오케스트레이션 비용 모델·spawn 표준·모델 판별 테스트
- [incident-casebook.md](docs/incident-casebook.md) — 사고 사례집(조용한 오판 A형 / 통신·생존 B형 / 기록 C형, 증상→경로→계기→비용→규칙)
- [verification-gates.md](docs/verification-gates.md) — 사례에서 도출한 검증 게이트 원칙(G1~G6 + 미해결 과제)

## 구조 — 2중 강제 장치

위임 원칙 위반을 막는 장치는 두 층으로 구성된다.

### 1. hookify warn 룰 (`hookify-rules/`)

- `hookify.delegate-file-edits.local.md` — 코드/설정 확장자(.py, .c, .sh, .json 등)에 대한 Edit/Write/MultiEdit 시 경고. `.md` 노트 등 문서 편집은 대상 아님.
- `hookify.delegate-heavy-bash.local.md` — 실행/빌드/테스트성 Bash 명령(python 스크립트 실행, pytest, make, gcc, pip install 등) 시 경고.
- `hookify.delegate-agent-model.local.md` — Agent spawn 시 model 미지정 또는 model=opus일 때 경고. sonnet 기본 원칙 참고.

터미널 UI에 표시되어 **사용자가 실시간으로 감시**할 수 있게 하는 용도다.

**주의:** hookify 플러그인은 세션 시작 시점의 cwd 기준 `.claude/` 디렉토리만 읽는다. 고정된 전역 경로를 읽지 않기 때문에, 이 저장소의 룰 파일을 프로젝트마다 직접 배포해야 실제로 작동한다. 배포 방법은 아래 "새 프로젝트 추가" 참조.

### 2. delegation-reminder.py 훅 (`hooks/`)

- PreToolUse 훅으로 동작하며, `hookSpecificOutput.additionalContext`를 통해 **모델의 컨텍스트 윈도우에 직접 리마인더를 주입**한다.
- hookify warn과 달리 이쪽은 모델이 실제로 "보는" 채널이다 (hookify warn의 `systemMessage`는 터미널에만 뜨고 모델 컨텍스트에는 들어가지 않는다).
- `~/.claude/settings.json`에 **글로벌로 등록**되어 있어 모든 프로젝트에서 공통 작동한다.
- 세션당 룰 종류별로 5분 스로틀이 걸려 있어, 같은 세션에서 반복 호출 시 토큰을 낭비하지 않는다.

이 저장소에서는 `hooks/delegation-reminder.py`가 원본이고, `~/.claude/hooks/delegation-reminder.py`는 이 파일로의 심링크다. `settings.json`이 `python3 ~/.claude/hooks/delegation-reminder.py` 경로를 참조하므로 이 경로 자체는 바꾸지 않는다.

## 점검 전담 에이전트(monitor) 패턴

**배경:** 오케스트레이터(Fable)가 백그라운드/원격 작업(Colab 실측, 장기 executor 등) 대기 중 wakeup마다 직접 깨어나 `colab ls`·아티팩트 `find`·에이전트 상태 질의를 반복하면, 고비용 모델이 단순 폴링에 소모된다. 세션 실측에서 wakeup당 6~7회의 직접 점검 호출이 관찰됨.

**규칙: 오케스트레이터는 백그라운드 작업을 직접 폴링하지 않는다.**

예상 소요 10분 이상인 장기 작업에 착수할 때는, 그 작업과 함께 점검 전담 Sonnet 에이전트(monitor)를 spawn한다.

- **monitor 임무:** (1) 대상 아티팩트 경로·세션명·작업 에이전트 이름을 인자로 받아 주기적으로 점검한다. (2) 정상 진행 중이면 침묵한다 — 오케스트레이터에게 보고하지 않는다. (3) 완료됐거나, 이상(아티팩트 미생성 상태로 예상 시간 초과, 세션 소멸, 작업 에이전트 무응답)이 감지된 경우에만 `SendMessage`로 오케스트레이터(team-lead 또는 메인 세션)에 에스컬레이션한다 — "예외 시에만 보고" 원칙.
- **오케스트레이터의 ScheduleWakeup:** monitor 자체가 죽었을 때를 대비한 장주기(30분 이상) 최후 안전망으로만 쓴다. 폴링 목적의 짧은 주기 wakeup은 monitor에게 위임한다.
- **점검 명령 시퀀스:** 기존 플레이북(아티팩트 확인 → 세션 생존 확인 → 작업 에이전트 상태 질의 → 2회 연속 실패 시 에스컬레이션)을 그대로 monitor 프롬프트에 넣어 위임한다.

### monitor spawn 프롬프트 템플릿

```
대상 아티팩트: <아티팩트 경로 또는 파일 패턴>
대상 세션: <원격 세션명, 예: colab 세션 또는 tmux 세션>
대상 작업 에이전트: <작업을 수행 중인 에이전트 이름/ID>
예상 소요: <분 단위 예상 완료 시간>

임무: 위 대상을 주기적으로 점검한다.
1. 아티팩트 경로 존재/갱신 확인.
2. 대상 세션 생존 확인(예: colab ls -s <세션명>).
3. 작업 에이전트 상태 질의(SendMessage로 생사 확인, 무응답이면 재시도 1회).
4. 정상 진행 중이면 아무 것도 하지 않고 다음 점검까지 대기한다 — 오케스트레이터에게 보고하지 않는다.
5. 완료를 확인했거나, 2회 연속 이상(아티팩트 미생성 초과 대기 / 세션 소멸 / 에이전트 무응답)이 감지되면
   즉시 SendMessage로 오케스트레이터에게 에스컬레이션한다.
```

이 패턴은 hookify 룰(`hookify.delegate-agent-model.local.md`)이나 `delegation-reminder.py`가 강제하는 model 명시 원칙과 별개로, "누가 폴링을 수행하는가"에 대한 위임 원칙이다. 두 원칙 모두 저비용 반복 작업을 고비용 오케스트레이터에서 걷어낸다는 같은 목표를 공유한다.

## 1단계 위임 원칙 (재위임 금지)

**근거:** 같은 세션에서 executor 재위임으로 인한 무응답 정지 사례가 2건 발생했다. 원인은 `delegation-reminder.py`가 PreToolUse 훅으로 동작하는 구조상 **오케스트레이터의 툴콜뿐 아니라 executor 서브에이전트 자신의 툴콜에도 동일하게 발동**한다는 데 있다. executor가 파일을 편집하거나 Bash를 실행할 때마다 "Sonnet 서브에이전트에 위임하라"는 리마인더가 executor 자신의 컨텍스트에 주입되고, executor가 이를 곧이곧대로 따라 자신의 하위에 또 다른 executor를 spawn하면서 재위임 체인이 발생 — 두 번째 executor는 부모로부터 결과를 받지 못하고 죽거나, 부모가 자식의 완료를 기다리며 무응답 상태로 정지했다.

**규칙: 위임은 1단계만 허용한다.** 오케스트레이터 → executor까지만 위임하고, executor는 자신이 받은 작업을 직접 실행해야 한다 — 그 작업이 아무리 "위임 대상처럼 보이는" 멀티파일 구현이라도 마찬가지다. executor가 재위임이 필요하다고 판단되는 규모의 작업을 받았다면, 그건 오케스트레이터가 애초에 작업을 더 잘게 쪼개서 위임했어야 한다는 신호이지, executor가 스스로 하위 체인을 만들어도 된다는 뜻이 아니다.

**대응:**
1. `delegation-reminder.py`가 주입하는 모든 리마인더 문구에 공통 헤더(`HEADER` 상수)를 두어 "이 리마인더는 메인 오케스트레이터 전용이며, 서브에이전트/executor는 무시하고 직접 실행하라 — 재위임 금지"를 명시적으로 반복한다. 기존 "서브에이전트는 무시" 한 줄만으로는 실제로 재위임을 막지 못했다.
2. 만약 spawn한 executor가 그럼에도 재위임을 시도해 무응답 정지가 관측되면: 결과를 기다리지 말고 즉시 상태를 확인(`git status`/`git log` 등 산출물 존재 여부)하고, 산출물이 없으면 그 체인을 폐기한 뒤 오케스트레이터가 직접 작업을 수행한다.

## 왜 block이 아니라 warn/리마인더인가

PreToolUse 훅은 메인 세션의 툴콜뿐 아니라 **서브에이전트의 툴콜에도 동일하게 발동**한다. 만약 Edit/Write를 `block`으로 막으면, 위임받은 executor 서브에이전트조차 파일을 편집할 수 없게 되어 위임 패턴 자체가 무너진다.

그래서 두 장치 모두 차단이 아닌 경고/리마인더로 설계했고, 리마인더 메시지에는 "서브에이전트라면 이 경고 무시하고 계속 진행"이 명시되어 있다. 판단은 메인 세션(Fable)의 몫으로 남긴다 — 트리비얼한 한 줄 수정은 직접 허용, 그 이상은 위임으로 전환하라는 신호만 준다.

## 새 프로젝트에 정책 추가하는 방법

1. `targets.txt`에 프로젝트 절대경로를 한 줄 추가.
2. `./sync.sh` 실행 — `targets.txt`의 모든 대상에 `hookify-rules/*.local.md`를 배포한다.
   - 특정 디렉토리만 동기화하려면 `./sync.sh <경로1> <경로2> ...`처럼 인자로 직접 지정.
   - 대상 디렉토리가 없으면 `skip (missing): <경로>`를 출력하고 다음 대상으로 계속 진행한다.
3. `delegation-reminder.py`는 이미 전역 등록되어 있으므로 프로젝트별 추가 작업이 필요 없다.

## settings.json 등록 스니펫 (참고용)

`delegation-reminder.py`는 아래처럼 `~/.claude/settings.json`의 `PreToolUse` 훅에 등록되어 있다 (이미 설정됨, 참고용으로만 기록):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Edit|Write|MultiEdit|ScheduleWakeup",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/hooks/delegation-reminder.py",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```
