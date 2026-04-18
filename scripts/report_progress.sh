#!/usr/bin/env bash
# scripts/report_progress.sh
# pain-collector Issue に build 進捗を 1 行コメントする.
#
# Usage:
#   ./scripts/report_progress.sh <issue_number> <source_repo> <stage> [<extra_message>]
#
# stage は固定の英数キー（preparing / validating / cloning / placing / building / pushing / done）。
# 同じ Issue に短時間で連続コメントが立つのを避けるため、呼び出し側で間引くこと。

set -euo pipefail

ISSUE="${1:?Usage: report_progress.sh <issue_number> <source_repo> <stage> [<extra>]}"
SOURCE="${2:?source_repo required}"
STAGE="${3:?stage required}"
EXTRA="${4:-}"

declare -A STAGE_LABELS=(
  ["preparing"]="🔧 build 準備中"
  ["validating"]="🔍 Spec を検証中"
  ["cloning"]="📥 product リポジトリを clone 中"
  ["placing"]="📝 Spec / Deep Dive を配置中"
  ["building"]="🤖 Claude Code で MVP 実装中"
  ["pushing"]="🚀 PR を作成中"
  ["done"]="✅ build 完了"
)

LABEL="${STAGE_LABELS[$STAGE]:-$STAGE}"
MESSAGE="$LABEL"
if [ -n "$EXTRA" ]; then
  MESSAGE="$MESSAGE — $EXTRA"
fi

echo "[report_progress] $ISSUE @ $SOURCE: $MESSAGE"

# 失敗しても build を止めない（通知優先度は低い）
gh issue comment "$ISSUE" --repo "$SOURCE" --body "$MESSAGE" || \
  echo "::warning::Failed to post progress comment (stage=$STAGE)"
