#!/usr/bin/env bash
# bench-t4-repeat-setup.sh 로 만든 worktree 6개(arm4-t4-r1~r3, arm6-t4-r1~r3)
# 정리. 결과 로그(~/workspace/.bench/results/*.log, *.jsonl)는 기본 보존 —
# --purge-results 로만 삭제.
#
# teardown 전 diff export 강제(9-arm 벤치와 동일 안전장치) — 미커밋 변경이
# 있으면 results/<name>.diff / <name>.stat 로 export 후에만 worktree 제거.

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

RUN_NAMES=(
  "arm4-t4-r1"
  "arm4-t4-r2"
  "arm4-t4-r3"
  "arm6-t4-r1"
  "arm6-t4-r2"
  "arm6-t4-r3"
)

cd "$REPO_DIR"

for name in "${RUN_NAMES[@]}"; do
  wt_path="$BENCH_ROOT/$name"
  if git worktree list --porcelain | grep -qF "worktree $wt_path"; then
    if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
      diff_file="$BENCH_ROOT/results/$name.diff"
      stat_file="$BENCH_ROOT/results/$name.stat"
      git -C "$wt_path" diff > "$diff_file"
      git -C "$wt_path" diff --stat > "$stat_file"
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
  rm -f "$BENCH_ROOT/results"/arm{4,6}-t4-r{1,2,3}.*
  echo "결과 로그 삭제됨"
else
  echo "결과 로그 보존: $BENCH_ROOT/results (삭제하려면 --purge-results)"
fi

echo ""
echo "남은 worktree:"
git worktree list

echo ""
echo "주의: 각 worktree를 cwd로 열어둔 터미널/세션이 남아 있으면 다음 명령"
echo "실행 시 ENOENT(posix_spawn)로 깨질 수 있음 — 실행 전 그 세션들을 먼저"
echo "안전한 디렉토리로 이동시키거나 닫을 것."
