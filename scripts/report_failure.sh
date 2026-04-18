#!/usr/bin/env bash
# scripts/report_failure.sh
# Claude Code 失敗時に pain-collector へエラー要約を返す.
#
# Usage:
#   ./scripts/report_failure.sh <issue_number> <source_repo> <product_repo> <build_log_path> <run_url>
#
# build.log の最後 N 行を抽出し Issue にコメント。
# Issue に build-failed ラベルを付与（building は外す）。

set -euo pipefail

ISSUE="${1:?issue_number required}"
SOURCE="${2:?source_repo required}"
PRODUCT="${3:?product_repo required}"
BUILD_LOG="${4:?build_log_path required}"
RUN_URL="${5:?run_url required}"
TAIL_LINES="${TAIL_LINES:-30}"

LOG_SNIPPET=""
if [ -f "$BUILD_LOG" ]; then
  LOG_SNIPPET=$(tail -n "$TAIL_LINES" "$BUILD_LOG" 2>/dev/null || echo "(build.log 読み込み失敗)")
else
  LOG_SNIPPET="(build.log が存在しません)"
fi

# Markdown コードフェンス内に埋め込むので、log 内の ``` を無害化
LOG_SNIPPET="${LOG_SNIPPET//\`\`\`/'```'}"

BODY=$(cat <<EOF
## ❌ MVP 自動生成に失敗したのだ

- リポジトリ: [$PRODUCT](https://github.com/$PRODUCT)
- ワークフローログ: $RUN_URL

### Claude Code 出力（末尾 $TAIL_LINES 行）

\`\`\`
$LOG_SNIPPET
\`\`\`

再実行する場合は \`/approve\` を再度コメントしてほしいのだ。
EOF
)

gh issue comment "$ISSUE" --repo "$SOURCE" --body "$BODY"

# building → build-failed
if ! gh issue edit "$ISSUE" --repo "$SOURCE" \
  --remove-label "building" --add-label "build-failed"; then
  echo "::warning::Failed to update labels on issue #$ISSUE"
fi
