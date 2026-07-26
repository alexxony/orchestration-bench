#!/usr/bin/env bash
# 오케스트레이션 방식 벤치마크용 worktree 4개 생성.
# 각 arm = 별도 폴더 + 별도 브랜치 → 동시 세션 실행해도 워킹 디렉토리 충돌 없음.
#
# arm1: model=sonnet, advisor=opus5
# arm2: model=opus5 단독
# arm3: model=opus5 오케스트레이터 + sonnet executor (구 fable 체제 마이그레이션)
# arm4: 기타 오케스트레이션 방식 (자유 배정)
#
# 실행: ./bench-setup.sh
# 결과: ~/workspace/.bench/<arm>/ 에 worktree, ~/workspace/.bench/results/<arm>.log 에 관측 기록 템플릿

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$HOME/workspace/.bench"
BASE_REF="master"

ARMS=(
  "arm1-sonnet-advopus:bench/arm1-sonnet-advopus"
  "arm2-opus:bench/arm2-opus"
  "arm3-opus-orch-sonnet-exec:bench/arm3-opus-orch-sonnet-exec"
  "arm4-other:bench/arm4-other"
)

cd "$REPO_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "경고: $REPO_DIR 에 미커밋 변경 있음. 커밋/스태시 후 재실행 권장." >&2
  git status --short >&2
  read -rp "그래도 계속? (y/N) " ans
  [[ "$ans" == "y" ]] || exit 1
fi

mkdir -p "$BENCH_ROOT/results"

for entry in "${ARMS[@]}"; do
  name="${entry%%:*}"
  branch="${entry##*:}"
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
# 벤치마크 로그 — $name

## 설정
- model:
- advisor:
- orchestration 방식:

## 태스크별 기록
(태스크 ID | 소요시간 | 토큰 | 툴콜 수 | 에러(bash 거부/권한 프롬프트/hook 충돌 등) | 결과물 diff 품질)

EOF
  fi
done

echo ""
echo "완료. worktree 목록:"
git worktree list
echo ""
echo "각 터미널에서:"
for entry in "${ARMS[@]}"; do
  name="${entry%%:*}"
  echo "  cd $BENCH_ROOT/$name  # $name"
done
