#!/usr/bin/env bash
# 후속 실험 — arm4(opus)·arm6(sonnet+advisor=on) T4 벽시계 지연(1062s·1330s
# 이상치) 원인 재현성 검증용 N=3 반복 worktree 생성 (2026-08-03 설계,
# 9-arm 벤치마크 미해결 과제 (4)항).
#
# 배경: 9-arm 종합(results-summary-6arm.md "T4 시간축 이상치" 절)에서
# arm4·arm6의 T4만 다른 arm(90~183s대)보다 10배 이상 큰 소요시간(1062s·
# 1330s)을 보임. diff 규모·toolcalls는 정상 자릿수라 실작업량 문제가
# 아니라 "벽시계 지연"(모델 응답 대기·턴 경계)으로 추정됐으나 N=1이라
# 재현성 미검증. 사용자 확인: T4만 재실행(전체 태스크셋 재실행 안 함),
# 반복 3회씩 독립 worktree/세션으로 격리(동일 세션 반복은 컨텍스트
# 오염 우려로 배제).
#
# 조건 매트릭스 (기존 9-arm과 동일 정의 유지, model/advisor만 반복):
#   arm4-t4-r1/r2/r3 : 구조=single, model=opus,   advisor=off
#   arm6-t4-r1/r2/r3 : 구조=single, model=sonnet, advisor=on(ORCH_RULE=on)
#
# 태스크: T4(bench-tasks.md 정의) 단독 — bench-setup.sh에 --dry-run 옵션
# 추가 후 직접 실행 검증. 지시문은 bench-tasks.md T4 절 그대로 사용.
#
# 실행: ./bench-t4-repeat-setup.sh
# 결과: ~/workspace/.bench/<name>/ 에 worktree,
#       ~/workspace/.bench/results/<name>.log(자유서술) +
#       ~/workspace/.bench/results/<name>.jsonl(기계가독, T4 1줄) 템플릿

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$HOME/workspace/.bench"
BASE_REF="master"

# entry 포맷: "이름:브랜치:모델:advisor"
RUNS=(
  "arm4-t4-r1:bench/arm4-t4-r1:opus:off"
  "arm4-t4-r2:bench/arm4-t4-r2:opus:off"
  "arm4-t4-r3:bench/arm4-t4-r3:opus:off"
  "arm6-t4-r1:bench/arm6-t4-r1:sonnet:on"
  "arm6-t4-r2:bench/arm6-t4-r2:sonnet:on"
  "arm6-t4-r3:bench/arm6-t4-r3:sonnet:on"
)

cd "$REPO_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "경고: $REPO_DIR 에 미커밋 변경 있음. 커밋/스태시 후 재실행 권장." >&2
  git status --short >&2
  read -rp "그래도 계속? (y/N) " ans
  [[ "$ans" == "y" ]] || exit 1
fi

mkdir -p "$BENCH_ROOT/results"

for entry in "${RUNS[@]}"; do
  IFS=':' read -r name branch model advisor <<<"$entry"
  wt_path="$BENCH_ROOT/$name"

  if git worktree list --porcelain | grep -qF "worktree $wt_path"; then
    echo "skip (already exists): $wt_path"
    continue
  fi

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$wt_path" "$branch"
  else
    git worktree add -b "$branch" "$wt_path" "$BASE_REF"
  fi
  echo "created: $wt_path (branch: $branch)"

  log_file="$BENCH_ROOT/results/$name.log"
  if [[ ! -f "$log_file" ]]; then
    cat > "$log_file" <<EOF
# T4 반복 실험 로그 — $name

## 설정 (스크립트가 미리 채움 — 세션 중 재구성 금지)
- 구조(structure): single
- 모델(model): $model
- advisor(ORCH_RULE): $advisor
- 태스크: T4 단독 (bench-tasks.md 정의 그대로)

## 지시문 (그대로 붙여넣을 것)
> bench-setup.sh에 --dry-run 옵션 추가해줘. 켜면 실제 git worktree add를
> 실행하지 않고 무엇을 할지(경로·브랜치명)만 출력. 추가 후 직접 실행해서
> 정상 동작 확인해줘.

## 기록
(소요시간 | 툴콜 수 | 위임 여부 | 에러 | diff 규모 | 벽시계 지연 재현 여부)

EOF
  fi

  jsonl_file="$BENCH_ROOT/results/$name.jsonl"
  [[ -f "$jsonl_file" ]] || : > "$jsonl_file"
done

echo ""
echo "완료. worktree 목록:"
git worktree list
echo ""
echo "각 터미널에서:"
for entry in "${RUNS[@]}"; do
  IFS=':' read -r name branch model advisor <<<"$entry"
  if [[ "$advisor" == "on" ]]; then
    echo "  cd $BENCH_ROOT/$name && ORCH_RULE=on claude --model $model  # $name"
  else
    echo "  cd $BENCH_ROOT/$name && claude --model $model  # $name"
  fi
done
echo ""
echo "각 세션에서 위 '## 지시문' 내용을 그대로 붙여넣고 T4만 단독 실행."
echo "완료 후 로그(<name>.log/.jsonl)에 소요시간·벽시계 지연 재현 여부 기록."
