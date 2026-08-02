#!/usr/bin/env bash
# 오케스트레이션 방식 벤치마크용 worktree 6개 생성 (2026-08-01 팩터 분리 재설계).
# 각 arm = 별도 폴더 + 별도 브랜치 → 동시 세션 실행해도 워킹 디렉토리 충돌 없음.
#
# 팩터 분리 설계 — 3축(구조/모델/advisor) 각각 독립 2셀, 교차 안 함.
# advisor(ORCH_RULE)는 텍스트로 "위임하라"를 직접 지시하는 명령이라 구조축과
# 겹침(비직교) — 그래서 교차 매트릭스가 아니라 축별 baseline-vs-treatment로 분리.
# baseline(struct=single, model=sonnet, advisor=off) 조건이 3개 arm에서
# 독립 반복됨 — 이는 세션 간 노이즈 추정용이지 어느 한 대조(contrast)의
# N=3을 뜻하지 않음(각 대조는 여전히 N=1 vs N=1).
#
# arm1 struct-single-base : 구조=단일세션, model=sonnet, advisor=off (기준셀)
# arm2 struct-orch         : 구조=오케스트레이터+executor 위임(하네스 조건,
#                             Agent 도구로 실제 subagent spawn 가능. 지시문으로
#                             위임 강제 안 함 — 오케스트레이터가 태스크마다
#                             자율 판단. 구 arm3 방식), model=sonnet, advisor=off
# arm3 model-sonnet-base   : 구조=단일세션, model=sonnet, advisor=off (기준셀 반복)
# arm4 model-opus          : 구조=단일세션, model=opus, advisor=off
# arm5 advisor-off-base    : 구조=단일세션, model=sonnet, advisor=off (기준셀 반복)
# arm6 advisor-on          : 구조=단일세션, model=sonnet, advisor=on(ORCH_RULE=on)
#
# model/advisor는 세션 시작 시 사용자가 직접 설정(스크립트가 강제 못 함) —
# 아래 각 arm 로그 템플릿에 "설정" 값을 미리 채워 넣어 세션 중 재구성 방지.
#
# 실행: ./bench-setup.sh
# 결과: ~/workspace/.bench/<arm>/ 에 worktree, ~/workspace/.bench/results/<arm>.log
#       (자유서술) + ~/workspace/.bench/results/<arm>.jsonl (기계가독, 태스크당 1줄)
#       템플릿 생성

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$HOME/workspace/.bench"
BASE_REF="master"

# entry 포맷: "arm이름:브랜치:구조:모델:advisor"
ARMS=(
  "arm1-struct-single-base:bench/arm1-struct-single-base:single:sonnet:off"
  "arm2-struct-orch:bench/arm2-struct-orch:orch:sonnet:off"
  "arm3-model-sonnet-base:bench/arm3-model-sonnet-base:single:sonnet:off"
  "arm4-model-opus:bench/arm4-model-opus:single:opus:off"
  "arm5-advisor-off-base:bench/arm5-advisor-off-base:single:sonnet:off"
  "arm6-advisor-on:bench/arm6-advisor-on:single:sonnet:on"
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
  IFS=':' read -r name branch struct model advisor <<<"$entry"
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

## 설정 (bench-setup.sh가 미리 채움 — 세션 중 재구성 금지)
- 구조(structure): $struct
- 모델(model): $model
- advisor(ORCH_RULE): $advisor

## 태스크별 기록
(태스크 ID | 소요시간 | 툴콜 수 | 위임 여부(직접/위임/분할) | 에러(bash 거부/권한 프롬프트/hook 충돌 등) | 결과물 diff 품질)

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
for entry in "${ARMS[@]}"; do
  IFS=':' read -r name branch struct model advisor <<<"$entry"
  echo "  cd $BENCH_ROOT/$name  # $name (구조=$struct model=$model advisor=$advisor)"
done
