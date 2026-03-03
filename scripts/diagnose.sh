#!/bin/bash
# scripts/diagnose.sh - 推論速度問題の診断
# 使い方: bash scripts/diagnose.sh

echo ""
echo "════════════════════════════════════════════"
echo "  🔍 Jetson LLM 速度診断"
echo "════════════════════════════════════════════"
echo ""

# 1. 電源モード
echo "【電源モード】"
sudo nvpmodel -q 2>/dev/null | grep -E "NV Power|Power" | head -3 || echo "  nvpmodel: 実行できません"
echo ""

# 2. GPU クロック
echo "【GPU クロック】"
cat /sys/devices/gpu.0/devfreq/*/cur_freq 2>/dev/null | awk '{printf "  現在: %d MHz\n", $1/1000000}' || \
  nvidia-smi --query-gpu=clocks.current.graphics --format=csv,noheader 2>/dev/null | head -1 | awk '{print "  現在:", $1, $2}'
cat /sys/devices/gpu.0/devfreq/*/max_freq 2>/dev/null | awk '{printf "  最大: %d MHz\n", $1/1000000}' || true
echo ""

# 3. メモリ
echo "【メモリ状態】"
TOTAL=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
FREE=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')
AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print int($2/1024)}')
echo "  合計: ${TOTAL} MB"
echo "  空き: ${FREE} MB"
echo "  利用可能: ${AVAIL} MB"
[ "$FREE" -lt 2000 ] && echo "  ⚠️  空きメモリ不足！sudo bash -c 'echo 3 > /proc/sys/vm/drop_caches'"
echo ""

# 4. llama.cpp CUDA確認
echo "【llama.cpp CUDA確認】"
LLAMA_CLI="$HOME/llama.cpp/build/bin/llama-cli"
if [ -f "$LLAMA_CLI" ]; then
  echo "  バイナリ: $LLAMA_CLI"
  if ldd "$LLAMA_CLI" 2>/dev/null | grep -q "libcuda\|libcublas"; then
    echo "  ✅ CUDA リンク: あり"
  else
    echo "  ❌ CUDA リンク: なし → CPU専用ビルド"
    echo "     → bash setup/05_setup_llamacpp.sh を再実行"
  fi
  # GGML_CUDA確認
  if strings "$LLAMA_CLI" 2>/dev/null | grep -q "GGML_CUDA\|cublas"; then
    echo "  ✅ GGML_CUDA: 有効"
  fi
else
  echo "  ❌ llama-cli が見つかりません"
fi
echo ""

# 5. モデル一覧
echo "【利用可能なGGUFモデル】"
find "$HOME/.ollama/models" -name "*.gguf" 2>/dev/null | while read f; do
  SIZE=$(du -sh "$f" 2>/dev/null | cut -f1)
  echo "  $SIZE  $f"
done
find "$HOME" -maxdepth 3 -name "*.gguf" 2>/dev/null | grep -v ".ollama" | while read f; do
  SIZE=$(du -sh "$f" 2>/dev/null | cut -f1)
  echo "  $SIZE  $f"
done | head -10
echo ""

# 6. GPU 使用率（現在）
echo "【GPU 現在の使用率】"
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
  --format=csv,noheader 2>/dev/null | \
  awk -F',' '{printf "  GPU使用率: %s | メモリ: %s / %s | 温度: %s\n", $1, $2, $3, $4}' || \
  echo "  nvidia-smi: 実行できません"
echo ""

# 7. ベンチマーク推奨コマンド
echo "【推奨: 速度ベンチマーク（GPUオフロードあり vs なし）】"
MODEL=$(find "$HOME/.ollama/models" -name "*.gguf" 2>/dev/null | head -1)
[ -z "$MODEL" ] && MODEL="/path/to/model.gguf"
echo ""
echo "  # CPU のみ（現在の状態に近い場合）:"
echo "  llama-cli -m '$MODEL' -ngl 0 -p 'test' -n 50 2>&1 | tail -5"
echo ""
echo "  # GPU 全オフロード（最適化後）:"
echo "  llama-cli -m '$MODEL' -ngl 999 --flash-attn -p 'test' -n 50 2>&1 | tail -5"
echo ""
echo "════════════════════════════════════════════"
