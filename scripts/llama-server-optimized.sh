#!/bin/bash
# scripts/llama-server-optimized.sh
# Jetson Orin Nano Super 最適化 llama-server 起動
# OpenAI互換 API: http://localhost:8081
#
# 使い方:
#   bash scripts/llama-server-optimized.sh [model.gguf]
#   bash scripts/llama-server-optimized.sh ~/.ollama/models/lfm25_gguf/LFM2.5-1.2B-Instruct-Q4_K_M.gguf

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

# ─── 設定 ───────────────────────────────────────────────────────────────────────
MODEL_PATH="${1:-$HOME/.ollama/models/lfm25_gguf/LFM2.5-1.2B-Instruct-Q4_K_M.gguf}"
PORT=8081
HOST="0.0.0.0"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

# Jetson Orin Nano Super 最適化パラメータ
N_GPU_LAYERS=999     # 全レイヤーGPUオフロード（必須）
CONTEXT_SIZE=4096    # コンテキストサイズ
BATCH_SIZE=512       # バッチサイズ
UBATCH_SIZE=512      # マイクロバッチサイズ
N_THREADS=6          # CPUスレッド（Orin Nano: 6コア）
PARALLEL=1           # 同時リクエスト数（メモリに応じて増やせる）

# ─── 前提チェック ────────────────────────────────────────────────────────────────
if [ ! -f "$LLAMA_SERVER" ]; then
  err "llama-server が見つかりません: $LLAMA_SERVER"
  echo "  → bash setup/05_setup_llamacpp.sh を実行してください"
  exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
  err "モデルが見つかりません: $MODEL_PATH"
  echo "  → 使い方: $0 /path/to/model.gguf"
  echo ""
  echo "  モデル候補:"
  find "$HOME/.ollama/models" -name "*.gguf" 2>/dev/null | head -10 | sed 's/^/    /'
  exit 1
fi

# ─── システム最適化 ──────────────────────────────────────────────────────────────
info "システム最適化を適用中..."

# MAXN 電源モード
sudo nvpmodel -m 0 2>/dev/null && ok "nvpmodel MAXN" || info "nvpmodel: スキップ"

# クロック固定
sudo jetson_clocks 2>/dev/null && ok "jetson_clocks" || info "jetson_clocks: スキップ"

# メモリキャッシュクリア
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true
ok "drop_caches"

# 空きメモリ確認
MEMFREE_MB=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')
info "空きメモリ: ${MEMFREE_MB} MB"

# ─── 起動 ───────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 llama-server 最適化起動"
echo "  モデル : $(basename $MODEL_PATH)"
echo "  GPU    : 全レイヤー (-ngl $N_GPU_LAYERS)"
echo "  Context: ${CONTEXT_SIZE} tokens"
echo "  API    : http://${HOST}:${PORT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  別ターミナルでGPU確認: watch -n 0.5 nvidia-smi"
echo "  動作テスト:"
echo "    curl http://localhost:${PORT}/v1/chat/completions \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"model\":\"lfm2.5\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}'"
echo ""

# 環境変数でCUDA最適化
# FORCE_MMQ: Q4_K_M等の量子化モデルでCUDA行列乗算を強制 (+10~30% speed)
export GGML_CUDA_FORCE_MMQ=1
export GGML_CUDA_NO_PEER_COPY=1
export CUDA_VISIBLE_DEVICES=0

exec "$LLAMA_SERVER" \
  --model "$MODEL_PATH" \
  --host "$HOST" \
  --port "$PORT" \
  -ngl "$N_GPU_LAYERS" \
  --flash-attn \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --ctx-size "$CONTEXT_SIZE" \
  --batch-size "$BATCH_SIZE" \
  --ubatch-size "$UBATCH_SIZE" \
  --threads "$N_THREADS" \
  --parallel "$PARALLEL" \
  --verbose \
  --log-prefix \
  2>&1
