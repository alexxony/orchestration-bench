#!/usr/bin/env bash
# results/*.jsonl 전부 읽어서 arm x task 비교 표를 stdout에 출력.
# jsonl 한 줄 스키마: {"arm":"...", "task":"T1", "elapsed_sec":15,
#   "toolcalls":4, "delegations":0, "errors":0, "files_changed":1,
#   "insertions":4, "deletions":0}
#
# 사용법: ./results/compare.sh
# python3 표준 라이브러리(json)만 사용 — 추가 의존성 없음.

set -euo pipefail

RESULTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$RESULTS_DIR" <<'PYEOF'
import json
import sys
import glob
import os

results_dir = sys.argv[1]
rows = []
for path in sorted(glob.glob(os.path.join(results_dir, "*.jsonl"))):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as e:
                print(f"경고: {path} 파싱 실패 — {e}", file=sys.stderr)

if not rows:
    print("jsonl 데이터 없음 — 각 arm 세션에서 태스크 완료 시 results/<arm>.jsonl에 기록 필요.")
    sys.exit(0)

cols = ["arm", "task", "elapsed_sec", "toolcalls", "delegations", "errors",
        "files_changed", "insertions", "deletions"]
widths = {c: max(len(c), max((len(str(r.get(c, ""))) for r in rows), default=0)) for c in cols}

def fmt_row(values):
    return " | ".join(str(v).ljust(widths[c]) for c, v in zip(cols, values))

print(fmt_row(cols))
print("-|-".join("-" * widths[c] for c in cols))
for r in sorted(rows, key=lambda r: (r.get("task", ""), r.get("arm", ""))):
    print(fmt_row([r.get(c, "") for c in cols]))

print()
print("## arm별 위임 발생 태스크 수")
by_arm = {}
for r in rows:
    arm = r.get("arm", "?")
    by_arm.setdefault(arm, {"total": 0, "delegated": 0})
    by_arm[arm]["total"] += 1
    if r.get("delegations", 0):
        by_arm[arm]["delegated"] += 1
for arm, v in sorted(by_arm.items()):
    print(f"- {arm}: {v['delegated']}/{v['total']}")
PYEOF
