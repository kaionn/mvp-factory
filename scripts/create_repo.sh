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
