#!/usr/bin/env bash
# scripts/validate_spec.sh
# Spec の YAML Front Matter を pain-collector の JSON Schema で検証する.
#
# Usage:
#   SPEC_PATH=/tmp/spec.md SOURCE_REPO=kaionn/pain-collector ./scripts/validate_spec.sh
#
# Front Matter がない legacy Spec は警告のみで通す（exit 0）.
# Schema fetch 失敗時もスキップして続行（運用を止めない）.
# Front Matter があり検証失敗の場合は exit 1.

set -euo pipefail

SPEC_PATH="${SPEC_PATH:?SPEC_PATH is required}"
SOURCE_REPO="${SOURCE_REPO:?SOURCE_REPO is required}"
SCHEMA_PATH="${SCHEMA_PATH:-/tmp/schema.json}"

if [ ! -f "$SPEC_PATH" ]; then
  echo "::error::Spec file not found: $SPEC_PATH"
  exit 1
fi

SCHEMA_URL="https://raw.githubusercontent.com/${SOURCE_REPO}/main/specs/schema.json"
if ! curl -fsSL "$SCHEMA_URL" -o "$SCHEMA_PATH"; then
  echo "::warning::Schema を取得できませんでした ($SCHEMA_URL)。検証をスキップして続行します。"
  exit 0
fi

pip install --quiet pyyaml jsonschema

SPEC_PATH="$SPEC_PATH" SCHEMA_PATH="$SCHEMA_PATH" python3 <<'PY'
import json
import os
import re
import sys

import yaml
from jsonschema import Draft7Validator

spec_path = os.environ['SPEC_PATH']
schema_path = os.environ['SCHEMA_PATH']

with open(spec_path, encoding='utf-8') as f:
    content = f.read()

fm_match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
if not fm_match:
    print('::warning::Front Matter が存在しない legacy Spec です。検証をスキップします。')
    sys.exit(0)

try:
    front_matter = yaml.safe_load(fm_match.group(1))
except yaml.YAMLError as exc:
    print(f'::error::Front Matter の YAML パースに失敗: {exc}')
    sys.exit(1)

if not isinstance(front_matter, dict):
    print('::error::Front Matter がオブジェクト形式ではありません')
    sys.exit(1)

with open(schema_path, encoding='utf-8') as f:
    schema = json.load(f)

validator = Draft7Validator(schema)
errors = sorted(validator.iter_errors(front_matter), key=lambda e: list(e.absolute_path))

if errors:
    for err in errors:
        path = '.'.join(str(p) for p in err.absolute_path) or '<root>'
        print(f'::error::Spec validation failure at {path}: {err.message}')
    sys.exit(1)

print('✅ Spec validation passed')
PY
