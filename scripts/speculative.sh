#!/bin/bash
# scripts/speculative.sh - 投機的デコーディング (Speculative Decoding)
#
# 小さいドラフトモデルで候補を生成 → 大きいモデルで検証
# 効果: 速度 2〜3x 向上（長文生成・チャットで特に効果大）
#
# 使い方:
#   bash scripts/speculative.sh                         # デフォルト設定
#   bash scripts/speculative.sh /path/main.gguf /path/draft.gguf

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

OLLAMA_DIR="$HOME/.ollama/models"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

# ─── モデル設定 ──────────────────────────────────────────────────────────────────
# メインモデル (品質担当) - 3.4GB
MAIN_MODEL="${1:-$(find $OLLAMA_DIR -name "*qwen3.5*4b*q4*" -o -name "*qwen2.5*7b*q4*" 2>/dev/null | head -1)}"
# ドラフトモデル (速度担当) - ~1GB 以下を選ぶ
DRAFT_MODEL="${2:-$(find $OLLAMA_DIR -name "*qwen3.5*0.8b*" -o -name "*qwen2.5*0.5b*" 2>/dev/null | head -1)}"

PORT=8082  # 通常の llama-server と別ポートで起動

# ─── 前提チェック ───────────────────────────────────────────────────────────────
if [ ! -f "$LLAMA_SERVER" ]; then
  err "llama-server が見つかりません: $LLAMA_SERVER"
  echo "  → bash setup/05_setup_llamacpp.sh を実行してください"
  exit 1
fi

if [ -z "$MAIN_MODEL" ] || [ ! -f "$MAIN_MODEL" ]; then
  err "メインモデル (4B) が見つかりません"
  echo "  → Ollama で pull: ollama pull qwen3.5:4b-q4_K_M"
  echo "  → または引数で指定: $0 /path/main.gguf /path/draft.gguf"
  exit 1
fi

if [ -z "$DRAFT_MODEL" ] || [ ! -f "$DRAFT_MODEL" ]; then
  err "ドラフトモデル (<1B) が見つかりません"
  echo "  → Ollama で pull: ollama pull qwen3.5:0.8b"
  echo "  → ドラフトなし通常モードで起動する場合: bash scripts/llama-server-optimized.sh"
  exit 1
fi

# ─── システム最適化 ──────────────────────────────────────────────────────────────
info "システム最適化を適用中..."
sudo nvpmodel -m 0 2>/dev/null && ok "nvpmodel MAXN" || true
sudo jetson_clocks 2>/dev/null && ok "jetson_clocks" || true
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

MEMFREE_MB=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 投機的デコーディング (Speculative Decoding)"
echo "  メイン  : $(basename $MAIN_MODEL)"
echo "  ドラフト: $(basename $DRAFT_MODEL)"
echo "  効果    : 推論速度 2〜3x 向上（理論値）"
echo "  空きRAM : ${MEMFREE_MB} MB"
echo "  API     : http://0.0.0.0:${PORT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

export GGML_CUDA_FORCE_MMQ=1
export GGML_CUDA_NO_VMM=1
export GGML_CUDA_NO_PEER_COPY=1
export CUDA_VISIBLE_DEVICES=0

exec "$LLAMA_SERVER" \
  --model         "$MAIN_MODEL" \
  --model-draft   "$DRAFT_MODEL" \
  --draft         8 \
  -ngl            999 \
  -ngld           999 \
  --flash-attn \
  --cache-type-k  q8_0 \
  --cache-type-v  q8_0 \
  --ctx-size      4096 \
  --batch-size    512 \
  --ubatch-size   512 \
  --threads       6 \
  --host          0.0.0.0 \
  --port          $PORT \
  --verbose \
  2>&1
