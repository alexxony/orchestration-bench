#!/usr/bin/env bash
# bench-setup.sh 로 만든 worktree 6개 정리.
# 결과 로그(~/workspace/.bench/results/*.log, *.jsonl)는 기본 보존 —
# --purge-results 로만 삭제.
#
# 2026-08-01 보강: teardown 전 diff export 강제. 1차 실행 때 arm 산출물이
# worktree에만 uncommitted로 존재하다 teardown으로 통째 소실된 사고
# (results-summary.md 손서술만 남음) 재발 방지 — 미커밋 변경이 있으면
# results/<arm>.diff / <arm>.stat 로 export 후에만 worktree 제거 허용.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$HOME/workspace/.bench"
PURGE_RESULTS=0

for arg in "$@"; do
  case "$arg" in
    --purge-results) PURGE_RESULTS=1 ;;
    *) echo "알 수 없는 옵션: $arg" >&2; exit 1 ;;
  esac
done

ARM_NAMES=(
  "arm1-struct-single-base"
  "arm2-struct-orch"
  "arm3-model-sonnet-base"
  "arm4-model-opus"
  "arm5-advisor-off-base"
  "arm6-advisor-on"
  "arm7-orch-opus"
  "arm8-orch-fable"
)

cd "$REPO_DIR"

for name in "${ARM_NAMES[@]}"; do
  wt_path="$BENCH_ROOT/$name"
  if git worktree list --porcelain | grep -qF "worktree $wt_path"; then
    if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
      diff_file="$BENCH_ROOT/results/$name.diff"
      stat_file="$BENCH_ROOT/results/$name.stat"
      git -C "$wt_path" diff > "$diff_file"
      git -C "$wt_path" diff --stat > "$stat_file"
      # untracked 파일은 diff에 안 잡히므로 별도 export
      git -C "$wt_path" status --porcelain | awk '/^\?\?/{print $2}' > "$BENCH_ROOT/results/$name.untracked-list"
      echo "diff export 완료: $diff_file / $stat_file (untracked 목록: $name.untracked-list)"
    fi
    git worktree remove --force "$wt_path"
    echo "removed worktree: $wt_path"
  else
    echo "skip (없음): $wt_path"
  fi
done

git worktree prune

if [[ "$PURGE_RESULTS" -eq 1 ]]; then
  rm -rf "$BENCH_ROOT/results"
  echo "결과 로그 삭제됨: $BENCH_ROOT/results"
else
  echo "결과 로그 보존: $BENCH_ROOT/results (삭제하려면 --purge-results)"
fi

echo ""
echo "남은 worktree:"
git worktree list

echo ""
echo "주의: 각 arm worktree를 cwd로 열어둔 터미널/세션이 남아 있으면 다음 명령"
echo "실행 시 ENOENT(posix_spawn)로 깨질 수 있음 — 실행 전 그 세션들을 먼저"
echo "안전한 디렉토리로 이동시키거나 닫을 것."
