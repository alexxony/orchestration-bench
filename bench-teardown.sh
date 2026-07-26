#!/usr/bin/env bash
# bench-setup.sh 로 만든 worktree 4개 정리.
# 결과 로그(~/workspace/.bench/results/*.log)는 기본 보존 — --purge-results 로만 삭제.

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
  "arm1-sonnet-advopus"
  "arm2-opus"
  "arm3-opus-orch-sonnet-exec"
  "arm4-other"
)

cd "$REPO_DIR"

for name in "${ARM_NAMES[@]}"; do
  wt_path="$BENCH_ROOT/$name"
  if git worktree list --porcelain | grep -qF "worktree $wt_path"; then
    if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
      echo "경고: $wt_path 에 미커밋 변경 있음 — 제거 건너뜀. 직접 확인할 것." >&2
      git -C "$wt_path" status --short >&2
      continue
    fi
    git worktree remove "$wt_path"
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
