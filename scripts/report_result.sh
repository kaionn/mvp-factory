#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/report_result.sh <issue_number> <source_repo> <product_repo> <pr_url>
ISSUE="${1:?}"
SOURCE="${2:?}"
PRODUCT="${3:?}"
PR_URL="${4:-}"

if [ -n "$PR_URL" ]; then
  BODY="## MVP 自動生成完了\n\n- リポジトリ: [$PRODUCT](https://github.com/$PRODUCT)\n- PR: $PR_URL"
else
  BODY="## MVP 自動生成でコード変更なし\n\nリポジトリ: [$PRODUCT](https://github.com/$PRODUCT)"
fi

gh issue comment "$ISSUE" --repo "$SOURCE" --body "$(echo -e "$BODY")"
