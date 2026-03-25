# mvp-factory

pain-collector で承認された MVP アイデアを受け取り、Claude Code で自動実装して新規リポジトリに PR を作成するオーケストレーター。

## 仕組み

```
kaionn/pain-collector          kaionn/mvp-factory           kaionn/{product}
━━━━━━━━━━━━━━━━━━          ━━━━━━━━━━━━━━━━━           ━━━━━━━━━━━━━━━
/approve コメント              build.yml が起動             テンプレートから生成
  → workflow_dispatch ───→   リポジトリ作成 ──────────→   Claude Code 実装
                              Claude Code 実行               PR 作成
                              結果報告 ────────────→       (pain-collector Issue に報告)
```

## セットアップ

### 1. GitHub Secrets の設定

リポジトリの Settings > Secrets and variables > Actions に以下を設定:

| Secret | 用途 |
|---|---|
| `ANTHROPIC_API_KEY` | Claude Code 実行 |
| `PAT_TOKEN` | リポジトリ作成、pain-collector への報告 |
| `VERCEL_TOKEN` | LP デプロイ（オプション） |

### 2. テンプレートリポジトリ

`kaionn/mvp-template` をテンプレートリポジトリとして用意する。

## 使い方

### pain-collector 経由（通常フロー）

pain-collector の Issue で `/approve` コメントすると、自動的に build.yml が dispatch される。

### 手動テスト

```bash
SPEC_CONTENT=$(echo "# Test Spec

## 要件
- テスト用の Hello World アプリ" | base64)

gh workflow run build.yml \
  --repo kaionn/mvp-factory \
  -f issue_number=1 \
  -f source_repo=kaionn/pain-collector \
  -f spec_content="$SPEC_CONTENT" \
  -f product_name="test-hello-world"
```

## ディレクトリ構成

```
mvp-factory/
├── .github/workflows/
│   └── build.yml              ← メイン: MVP 生成ワークフロー
├── scripts/
│   ├── create_repo.sh         ← テンプレートからリポジトリ作成
│   └── report_result.sh       ← pain-collector Issue に結果報告
├── config/
│   ├── claude-plugins.json    ← 使用するプラグイン設定
│   └── deploy-targets.json    ← デプロイ先設定
├── templates/
│   └── claude-prompt.md       ← Claude Code に渡すプロンプトテンプレート
├── CLAUDE.md
├── Plan.md
└── README.md
```

## ライセンス

MIT
