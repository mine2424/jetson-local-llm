#!/bin/bash
# ベンチマーク: tokens/sec + TTFT 計測
set -e

RESULTS_DIR="$(dirname $0)/results"
mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$RESULTS_DIR/bench_$TIMESTAMP.md"

MODELS=(
  "qwen2.5:7b"
  "qwen2.5:3b"
  "phi3.5:mini"
  "gemma2:2b"
  "lfm2.5:3b"
)

PROMPT="日本語で「機械学習とは何か」を200文字程度で説明してください。"

echo "# Benchmark Results - $TIMESTAMP" > "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "| Model | tokens/sec | TTFT(ms) | Total tokens |" >> "$RESULT_FILE"
echo "|-------|-----------|----------|-------------|" >> "$RESULT_FILE"

for MODEL in "${MODELS[@]}"; do
  # モデルが存在するか確認
  if ! ollama list | grep -q "^$MODEL"; then
    echo "⏭️  Skipping $MODEL (not installed)"
    continue
  fi

  echo "Benchmarking: $MODEL ..."
  
  START=$(date +%s%N)
  RESPONSE=$(ollama run "$MODEL" "$PROMPT" 2>/dev/null || echo "ERROR")
  END=$(date +%s%N)

  ELAPSED_MS=$(( (END - START) / 1000000 ))
  TOKEN_COUNT=$(echo "$RESPONSE" | wc -w)
  TPS=$(echo "scale=1; $TOKEN_COUNT * 1000 / $ELAPSED_MS" | bc 2>/dev/null || echo "N/A")

  echo "| $MODEL | $TPS | ~$ELAPSED_MS | $TOKEN_COUNT |" >> "$RESULT_FILE"
  echo "  → $TPS tokens/sec (${ELAPSED_MS}ms)"
done

echo ""
cat "$RESULT_FILE"
echo ""
echo "✅ Results saved: $RESULT_FILE"
