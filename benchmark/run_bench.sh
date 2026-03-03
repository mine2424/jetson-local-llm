#!/bin/bash
# ベンチマーク: tokens/sec + TTFT 計測
# Ollama HTTP API 経由 (/api/generate, /api/tags) を使用
# jetson-containers Docker コンテナ対応

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
OLLAMA_API="http://localhost:11434"

mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$RESULTS_DIR/bench_$TIMESTAMP.md"

# Ollama API 起動確認
if ! curl -s "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
  echo "❌ Ollama API が応答しません (http://localhost:11434)"
  echo "   コンテナが起動しているか確認してください:"
  echo "   sudo docker ps --filter name=ollama"
  exit 1
fi

# インストール済みモデルを API から取得
MODELS=$(curl -s "$OLLAMA_API/api/tags" | \
  python3 -c "import sys,json; [print(m['name']) for m in json.load(sys.stdin)['models']]" 2>/dev/null)

if [ -z "$MODELS" ]; then
  echo "❌ インストール済みモデルがありません"
  echo "   モデルをダウンロードしてください:"
  echo "   curl -X POST $OLLAMA_API/api/pull -d '{\"name\":\"qwen2.5:3b\"}'"
  exit 1
fi

PROMPT="日本語で「機械学習とは何か」を200文字程度で説明してください。"

echo "# Benchmark Results - $TIMESTAMP"
echo ""
echo "Device : Jetson Orin Nano Super"
echo "API    : $OLLAMA_API"
echo "Prompt : $PROMPT"
echo ""

{
  echo "# Benchmark Results"
  echo "- Date: $(date)"
  echo "- Device: Jetson Orin Nano Super"
  echo "- Prompt: $PROMPT"
  echo ""
  echo "| Model | tokens/sec | eval_ms | prompt_ms | tokens |"
  echo "|-------|-----------|---------|-----------|--------|"
} > "$RESULT_FILE"

while IFS= read -r MODEL; do
  echo "Benchmarking: $MODEL ..."

  # NvMap 用にページキャッシュ解放
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true

  # /api/generate (stream=false) で推論 → eval_count / eval_duration を取得
  API_RESULT=$(curl -s -X POST "$OLLAMA_API/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json; print(json.dumps({
      'model': '$MODEL',
      'prompt': '$PROMPT',
      'stream': False
    }))")" 2>/dev/null || echo '{}')

  # Python で結果をパース
  python3 - <<PYEOF >> "$RESULT_FILE"
import json, sys

raw = '''$API_RESULT'''
try:
    d = json.loads(raw)
    if 'error' in d:
        print(f"| $MODEL | ERROR | - | - | - |")
        sys.exit(0)

    eval_count    = d.get('eval_count', 0)         # 生成トークン数
    eval_dur_ns   = d.get('eval_duration', 1)       # 生成時間(ns)
    prompt_dur_ns = d.get('prompt_eval_duration', 0) # プロンプト評価時間(ns)

    eval_ms   = int(eval_dur_ns / 1e6)
    prompt_ms = int(prompt_dur_ns / 1e6)
    tps       = round(eval_count / (eval_dur_ns / 1e9), 1) if eval_dur_ns > 0 else 0

    print(f"| $MODEL | {tps} | {eval_ms} | {prompt_ms} | {eval_count} |")
except Exception as e:
    print(f"| $MODEL | PARSE_ERROR | - | - | - |")
PYEOF

  # ターミナルにもサマリ出力
  python3 - <<PYEOF
import json, sys

raw = '''$API_RESULT'''
try:
    d = json.loads(raw)
    eval_count  = d.get('eval_count', 0)
    eval_dur_ns = d.get('eval_duration', 1)
    tps = round(eval_count / (eval_dur_ns / 1e9), 1) if eval_dur_ns > 0 else 0
    print(f"  → {tps} tokens/sec  ({eval_count} tokens)")
except:
    print("  → 計測失敗")
PYEOF

  # 次のモデルの前にモデルをアンロード (メモリ解放)
  curl -s -X POST "$OLLAMA_API/api/generate" \
    -d "{\"model\": \"$MODEL\", \"keep_alive\": 0}" > /dev/null 2>&1 || true

done <<< "$MODELS"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$RESULT_FILE"
echo ""
echo "✅ Results saved: $RESULT_FILE"
