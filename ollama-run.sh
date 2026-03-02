#!/usr/bin/env bash
# ollama-run.sh — コンテナ内の ollama run を手軽に呼ぶラッパー
#
# Usage:
#   ./ollama-run.sh <model>
#   ./ollama-run.sh qwen2.5:3b
#   ./ollama-run.sh          # ← 引数なし: インストール済みモデル一覧を表示

set -euo pipefail

MODEL="${1:-}"

if [ -z "$MODEL" ]; then
  echo "Usage: $0 <model>"
  echo ""
  echo "インストール済みモデル:"
  curl -s http://localhost:11434/api/tags 2>/dev/null \
    | python3 -c "import sys,json; [print(' -', m['name']) for m in json.load(sys.stdin).get('models',[])]" \
    2>/dev/null || echo "  (Ollama が起動していないか API に到達できません)"
  echo ""
  echo "例:"
  echo "  $0 qwen2.5:3b"
  exit 1
fi

# コンテナが起動しているか確認
if ! sudo docker ps --filter name=ollama --filter status=running \
       --format '{{.Names}}' 2>/dev/null | grep -q '^ollama$'; then
  echo "❌  ollama コンテナが起動していません。先に起動してください:"
  echo "    sudo docker start ollama"
  echo "    # または: bash menu.sh → 3. Service → 2. Ollama 起動"
  exit 1
fi

echo "💬  ollama run $MODEL  (終了: /bye または Ctrl+D)"
exec sudo docker exec -it ollama ollama run "$MODEL"
