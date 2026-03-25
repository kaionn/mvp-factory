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
