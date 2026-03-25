# mvp-factory Plan

## このリポジトリの目的

pain-collector で承認された MVP アイデアを受け取り、Claude Code + compound-engineering で自動実装して新規リポジトリに PR を作成するオーケストレーター。

pain-collector の `/approve` コメント → mvp-factory の build.yml が dispatch される → テンプレートからリポジトリ作成 → Claude Code で実装 → PR 作成 → 結果を pain-collector に報告。

## 全体アーキテクチャ内での位置づけ

```
kaionn/pain-collector          kaionn/mvp-factory           kaionn/{product}
━━━━━━━━━━━━━━━━━━          ━━━━━━━━━━━━━━━━━           ━━━━━━━━━━━━━━━
/approve コメント              build.yml が起動             テンプレートから生成
  → workflow_dispatch ───→   リポジトリ作成 ──────────→   Claude Code 実装
                              Claude Code 実行               PR 作成
                              結果報告 ────────────→       (pain-collector Issue に報告)
```

## 最終的なディレクトリ構成

```
mvp-factory/
├── .github/
│   └── workflows/
│       ├── build.yml              ← メイン: MVP 生成ワークフロー
│       └── deploy-lp.yml          ← オプション: LP デプロイ
├── scripts/
│   ├── create_repo.sh             ← テンプレートからリポジトリ作成
│   ├── run_claude.sh              ← Claude Code セッション実行
│   ├── generate_lp.py             ← LP HTML 自動生成
│   └── report_result.sh           ← pain-collector Issue に結果報告
├── config/
│   ├── claude-plugins.json        ← 使用するプラグイン設定
│   └── deploy-targets.json        ← デプロイ先設定
├── templates/
│   └── claude-prompt.md           ← Claude Code に渡すプロンプトテンプレート
├── CLAUDE.md
├── Plan.md                        ← このファイル
├── README.md
└── LICENSE
```

---

## セキュリティ設定（Task 1 と同時に実施）

リポジトリ作成直後に以下を必ず設定する。kaionn 以外の操作を最大限制限する。

### 1. Branch Protection（main ブランチ）

```bash
gh api repos/kaionn/mvp-factory/branches/main/protection -X PUT \
  -H "Accept: application/vnd.github+json" \
  --input - << 'JSON'
{
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": false
  },
  "enforce_admins": false,
  "required_status_checks": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

### 2. 全ワークフローに actor ガードを追加

全ての `workflow_dispatch` 付きワークフローの jobs に以下の条件を追加:

```yaml
jobs:
  build:
    if: github.event_name == 'schedule' || github.actor == 'kaionn'
```

build.yml は外部から dispatch される可能性があるため、入力の `source_repo` も検証する:

```yaml
- name: Validate caller
  run: |
    SOURCE="${{ github.event.inputs.source_repo }}"
    if [[ "$SOURCE" != kaionn/* ]]; then
      echo "::error::Unauthorized source repo: $SOURCE"
      exit 1
    fi
```

### 3. CODEOWNERS

```
# リポジトリ全体の変更に kaionn のレビューを推奨
* @kaionn
```

---

## 実装タスク（上から順に実施）

### Task 1: リポジトリ初期化

GitHub リポジトリを作成し、基本構成を整える。

```bash
cd /Users/aucks/dev/src/github.com/kaionn/mvp-factory
git init
gh repo create kaionn/mvp-factory --public --source=. --push
```

作成するファイル:
- `README.md` — リポジトリの説明
- `LICENSE` — MIT
- `.gitignore` — Python + Node.js
- `CLAUDE.md` — このリポジトリでの Claude Code の振る舞い

`CLAUDE.md` の内容:
```markdown
# mvp-factory

MVP 自動生成のオーケストレーター。

## このリポジトリで行うこと
- GitHub Actions ワークフローの開発
- シェルスクリプト / Python スクリプトの開発
- Claude Code プロンプトテンプレートの作成

## コーディング規約
- シェルスクリプト: set -euo pipefail を先頭に付ける
- Python: 型ヒント必須、f-string 使用
- ワークフロー: 各 step に name を付ける
```

---

### Task 2: build.yml（メインワークフロー）

pain-collector の approve.yml から dispatch されるメインワークフロー。

`.github/workflows/build.yml`:
```yaml
name: Build MVP

on:
  workflow_dispatch:
    inputs:
      issue_number:
        description: 'pain-collector の Issue 番号'
        required: true
        type: string
      source_repo:
        description: 'pain-collector のリポジトリ (owner/repo)'
        required: true
        type: string
      spec_content:
        description: 'Spec ファイルの内容 (base64)'
        required: true
        type: string
      deep_dive_content:
        description: 'Deep Dive の内容 (base64、空の場合あり)'
        required: false
        type: string
        default: ''
      product_name:
        description: 'プロダクト名 (ケバブケース)'
        required: true
        type: string

env:
  PRODUCT_REPO: kaionn/${{ github.event.inputs.product_name }}

jobs:
  create-repo:
    runs-on: ubuntu-latest
    outputs:
      repo_created: ${{ steps.create.outputs.created }}
    steps:
      - uses: actions/checkout@v4

      - name: Create product repository from template
        id: create
        env:
          GITHUB_TOKEN: ${{ secrets.PAT_TOKEN }}
        run: |
          # テンプレートからリポジトリ作成
          if gh repo view "$PRODUCT_REPO" &>/dev/null; then
            echo "Repository already exists"
            echo "created=false" >> $GITHUB_OUTPUT
          else
            gh repo create "$PRODUCT_REPO" \
              --template kaionn/mvp-template \
              --public \
              --clone=false
            echo "created=true" >> $GITHUB_OUTPUT
          fi

      - name: Clone product repository
        env:
          GITHUB_TOKEN: ${{ secrets.PAT_TOKEN }}
        run: |
          gh repo clone "$PRODUCT_REPO" product-repo

      - name: Place spec and deep dive files
        run: |
          cd product-repo
          mkdir -p docs

          # Spec を配置
          echo "${{ github.event.inputs.spec_content }}" | base64 -d > docs/spec.md

          # Deep Dive を配置（存在する場合）
          DEEP_DIVE="${{ github.event.inputs.deep_dive_content }}"
          if [ -n "$DEEP_DIVE" ]; then
            echo "$DEEP_DIVE" | base64 -d > docs/deep-dive.md
          fi

          # pain-collector Issue への参照を記録
          cat > docs/origin.md << ORIGIN
          # Origin
          - pain-collector Issue: ${{ github.event.inputs.source_repo }}#${{ github.event.inputs.issue_number }}
          - Generated by: kaionn/mvp-factory
          - Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
          ORIGIN

          git add .
          git commit -m "docs: Spec と Deep Dive を配置"
          git push

      - name: Upload product-repo as artifact
        uses: actions/upload-artifact@v4
        with:
          name: product-repo
          path: product-repo/

  build-with-claude:
    needs: create-repo
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - name: Download product-repo artifact
        uses: actions/download-artifact@v4
        with:
          name: product-repo
          path: product-repo/

      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code

      - name: Install compound-engineering plugin
        run: |
          cd product-repo
          claude plugin marketplace add EveryInc/compound-engineering-plugin
          claude plugin install compound-engineering

      - name: Run Claude Code with spec
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          cd product-repo

          # プロンプトテンプレートを展開
          SPEC_PATH="docs/spec.md"
          PROMPT=$(cat ${{ github.workspace }}/templates/claude-prompt.md | sed "s|{{SPEC_PATH}}|$SPEC_PATH|g")

          # Claude Code 実行
          claude -p "$PROMPT" \
            --allowedTools '*' \
            --output-format text \
            --max-turns 100 \
            > ../build.log 2>&1 || true

          echo "--- Build Log (last 50 lines) ---"
          tail -50 ../build.log

      - name: Push changes and create PR
        env:
          GITHUB_TOKEN: ${{ secrets.PAT_TOKEN }}
        run: |
          cd product-repo

          # 変更があれば feature ブランチで PR 作成
          if [ -n "$(git status --porcelain)" ]; then
            BRANCH="feat/initial-mvp"
            git checkout -b "$BRANCH"
            git add -A
            git commit -m "feat: MVP 初期実装（Claude Code 自動生成）"
            git push -u origin "$BRANCH"

            PR_URL=$(gh pr create \
              --title "feat: MVP 初期実装" \
              --body "$(cat <<PR_BODY
          ## 概要

          pain-collector Issue #${{ github.event.inputs.issue_number }} から自動生成された MVP の初期実装。

          ## 生成元
          - Spec: docs/spec.md
          - Deep Dive: docs/deep-dive.md（存在する場合）
          - pain-collector: ${{ github.event.inputs.source_repo }}#${{ github.event.inputs.issue_number }}

          ## 生成方法
          - Claude Code + compound-engineering plugin
          - ワークフロー: kaionn/mvp-factory build.yml

          ---
          🤖 自動生成 by mvp-factory
          PR_BODY
            )" \
              --head "$BRANCH" \
              --base main)

            echo "PR_URL=$PR_URL" >> $GITHUB_ENV
          else
            echo "No changes generated"
            echo "PR_URL=" >> $GITHUB_ENV
          fi

      - name: Report result to pain-collector
        env:
          GITHUB_TOKEN: ${{ secrets.PAT_TOKEN }}
        run: |
          ISSUE="${{ github.event.inputs.issue_number }}"
          SOURCE="${{ github.event.inputs.source_repo }}"
          PRODUCT="${{ env.PRODUCT_REPO }}"

          if [ -n "$PR_URL" ]; then
            COMMENT="## 🚀 MVP 自動生成完了

          - リポジトリ: [$PRODUCT](https://github.com/$PRODUCT)
          - PR: $PR_URL
          - ステータス: PR レビュー待ち

          次のステップ:
          1. PR をレビューしてマージ
          2. デプロイ設定（Vercel 等）
          3. LP でウェイトリスト収集"
          else
            COMMENT="## ⚠️ MVP 自動生成で変更なし

          Claude Code の実行は完了しましたが、コード変更が生成されませんでした。
          ビルドログを確認してください。

          リポジトリ: [$PRODUCT](https://github.com/$PRODUCT)"
          fi

          gh issue comment "$ISSUE" --repo "$SOURCE" --body "$COMMENT"

          # ステータスラベル更新
          if [ -n "$PR_URL" ]; then
            gh issue edit "$ISSUE" --repo "$SOURCE" \
              --remove-label "building" --add-label "pr-created" 2>/dev/null || true
          fi
```

---

### Task 3: Claude Code プロンプトテンプレート

`templates/claude-prompt.md`:
```markdown
あなたは MVP を自動実装するエンジニアです。

## 手順

1. まず docs/spec.md を読み込んでください
2. docs/deep-dive.md が存在すれば、競合分析やペルソナ情報として参照してください
3. 以下の順序で実装を進めてください:

### Step 1: /ce:brainstorm
- Spec を入力として要件を確認・補強
- 不明確な箇所は Spec の文脈から推測して判断（質問はしない）

### Step 2: /ce:plan
- Spec の技術スタックに従って設計
- Implementation Units に分割
- テスト戦略を含める

### Step 3: /ce:work
- Plan に従って実装
- テストを書く
- README.md にセットアップ手順を記載

### Step 4: /ce:review
- コードレビューを実行
- 指摘事項があれば修正

## 制約
- 対話的な質問はしない（全自動実行のため）
- 迷ったら Spec の内容を優先
- MVP として最小限のスコープに留める
- テストは必ず書く

## Spec ファイル
{{SPEC_PATH}}
```

---

### Task 4: scripts/ の実装

各スクリプトを実装する。build.yml から呼び出されるヘルパー。

`scripts/create_repo.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/create_repo.sh <product-name>
PRODUCT_NAME="${1:?Usage: create_repo.sh <product-name>}"
REPO="kaionn/${PRODUCT_NAME}"

if gh repo view "$REPO" &>/dev/null; then
  echo "[create_repo] Repository $REPO already exists"
  exit 0
fi

gh repo create "$REPO" --template kaionn/mvp-template --public --clone=false
echo "[create_repo] Created $REPO from template"
```

`scripts/report_result.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/report_result.sh <issue_number> <source_repo> <product_repo> <pr_url>
ISSUE="${1:?}"
SOURCE="${2:?}"
PRODUCT="${3:?}"
PR_URL="${4:-}"

if [ -n "$PR_URL" ]; then
  BODY="## 🚀 MVP 自動生成完了\n\n- リポジトリ: [$PRODUCT](https://github.com/$PRODUCT)\n- PR: $PR_URL"
else
  BODY="## ⚠️ MVP 自動生成でコード変更なし\n\nリポジトリ: [$PRODUCT](https://github.com/$PRODUCT)"
fi

gh issue comment "$ISSUE" --repo "$SOURCE" --body "$(echo -e "$BODY")"
```

---

### Task 5: config/ の作成

`config/claude-plugins.json`:
```json
{
  "plugins": [
    {
      "name": "compound-engineering",
      "source": "EveryInc/compound-engineering-plugin",
      "required": true
    }
  ]
}
```

`config/deploy-targets.json`:
```json
{
  "default": "vercel",
  "targets": {
    "vercel": {
      "command": "npx vercel --prod --yes",
      "requires": ["VERCEL_TOKEN"]
    },
    "github-pages": {
      "command": "gh-pages -d out",
      "requires": []
    }
  }
}
```

---

### Task 6: deploy-lp.yml（オプション、後から追加可能）

LP 生成・デプロイのワークフロー。MVP 本体とは別に、需要検証用の Landing Page をデプロイする。

これは #67 (LP 需要検証) に対応する。初期実装では省略可能。

---

### Task 7: README.md の作成

リポジトリの説明、セットアップ手順、使い方を記載する。

---

## 実行順序まとめ

```
Task 1: リポジトリ初期化（git init, gh repo create, CLAUDE.md）
  ↓
Task 2: build.yml（メインワークフロー）
  ↓
Task 3: claude-prompt.md（プロンプトテンプレート）
  ↓
Task 4: scripts/（ヘルパースクリプト）
  ↓
Task 5: config/（設定ファイル）
  ↓
Task 7: README.md
  ↓
(完了後) pain-collector #73 の実装（dispatch 先の変更）
```

## 必要な GitHub Secrets

mvp-factory リポジトリの Settings > Secrets に以下を設定:

| Secret | 用途 | 取得方法 |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude Code 実行 | https://console.anthropic.com/ |
| `PAT_TOKEN` | リポジトリ作成、pain-collector への報告 | GitHub Settings > Developer settings > Personal access tokens（スコープ: repo, workflow） |
| `VERCEL_TOKEN` | LP デプロイ（オプション） | https://vercel.com/account/tokens |

## テスト方法

1. 手動で build.yml を dispatch してテスト:
   ```bash
   SPEC_CONTENT=$(echo "# Test Spec\n\n## 要件\n- テスト用の Hello World アプリ" | base64)
   gh workflow run build.yml \
     --repo kaionn/mvp-factory \
     -f issue_number=1 \
     -f source_repo=kaionn/pain-collector \
     -f spec_content="$SPEC_CONTENT" \
     -f product_name="test-hello-world"
   ```
2. kaionn/test-hello-world リポジトリが作成されるか確認
3. PR が作成されるか確認
4. pain-collector の Issue にコメントが投稿されるか確認
