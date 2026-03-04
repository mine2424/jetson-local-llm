#!/bin/bash
# setup/09_optimize_perf.sh - Jetson Orin Nano Super パフォーマンス最適化
#
# 目的:
#   llama.cpp の推論速度を最大化する
#   デフォルト設定(CPU推論 ~7 t/s) → GPU全オフロード(目標 40〜60 t/s)
#
# 実行例:
#   bash setup/09_optimize_perf.sh
#   bash setup/09_optimize_perf.sh --apply   # 設定を即時適用

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
info()  { echo -e "${YELLOW}[--]${NC} $*"; }
err()   { echo -e "${RED}[NG]${NC} $*"; }
head_()  { echo -e "${CYAN}$*${NC}"; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

echo ""
echo "══════════════════════════════════════════════════════"
echo "  ⚡ Jetson Orin Nano Super — 推論速度最適化"
echo "══════════════════════════════════════════════════════"
echo ""

# ─── [1] 現状診断 ──────────────────────────────────────────────────────────────
head_ "── [1/5] 現状診断 ──"

# 電源モード確認
CURRENT_POWER=$(sudo nvpmodel -q 2>/dev/null | grep "NV Power Mode" | awk '{print $NF}' || echo "UNKNOWN")
info "現在の電源モード: $CURRENT_POWER"
if [[ "$CURRENT_POWER" != *"MAXN"* ]]; then
  echo -e "  ${RED}⚠️  MAXN モードではありません！パフォーマンスが制限されています${NC}"
else
  ok "MAXN モード動作中"
fi

# クロック確認
if sudo jetson_clocks --show 2>/dev/null | grep -q "CPU Cluster"; then
  ok "jetson_clocks 設定済み"
else
  info "jetson_clocks: 未適用（クロックが抑制される可能性あり）"
fi

# GPU メモリ空き確認
MEMFREE_MB=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')
info "空きメモリ: ${MEMFREE_MB} MB / 8192 MB"
if [ "$MEMFREE_MB" -lt 2000 ]; then
  echo -e "  ${RED}⚠️  空きメモリが少ない！drop_caches を推奨${NC}"
fi

# llama.cpp CUDA ビルド確認
LLAMA_BIN=""
for p in "$HOME/llama.cpp/build/bin/llama-cli" "/usr/local/bin/llama-cli"; do
  if [ -f "$p" ]; then
    LLAMA_BIN="$p"
    break
  fi
done

if [ -n "$LLAMA_BIN" ]; then
  LLAMA_BIN_DIR="$(dirname "$LLAMA_BIN")"
  # 新しい llama.cpp は CUDA バックエンドを libggml-cuda.so として分離している
  # ldd で libcuda を探す従来の方法は機能しない (dlopen されるため)
  if ls "$LLAMA_BIN_DIR"/libggml-cuda.so* >/dev/null 2>&1; then
    ok "llama-cli: CUDA ビルド確認済み (libggml-cuda.so あり)"
  else
    err "llama-cli: CUDA ビルドなし (libggml-cuda.so が見つからない)"
    echo "  → Setup → 4. llama.cpp ビルド単体 を再実行してください"
  fi
else
  err "llama-cli が見つかりません → bash setup/05_setup_llamacpp.sh を実行してください"
fi

# Ollama コンテナの GPU 環境変数確認
if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"; then
  CONTAINER_ENV=$(sudo docker inspect ollama --format '{{range .Config.Env}}{{.}} {{end}}' 2>/dev/null || true)
  if echo "$CONTAINER_ENV" | grep -q "GGML_CUDA_NO_VMM=1"; then
    ok "Ollama: GGML_CUDA_NO_VMM=1 設定済み"
  else
    err "Ollama: GGML_CUDA_NO_VMM=1 未設定 → GPU 割り当てが失敗する可能性あり"
    echo "  → bash setup/08_setup_jetson_containers.sh を再実行してください"
  fi
  if echo "$CONTAINER_ENV" | grep -q "OLLAMA_NUM_GPU=999"; then
    ok "Ollama: OLLAMA_NUM_GPU=999 設定済み"
  else
    err "Ollama: OLLAMA_NUM_GPU=999 未設定 → 一部レイヤーが CPU 推論になる可能性あり"
    echo "  → bash setup/08_setup_jetson_containers.sh を再実行してください"
  fi
else
  info "Ollama コンテナ未起動 (GPU 環境変数の確認をスキップ)"
fi

echo ""

# ─── [2] 設定適用 ──────────────────────────────────────────────────────────────
head_ "── [2/5] 電源・クロック最適化 ──"

if $APPLY; then
  # MAXN モード（最大パフォーマンス）
  # ID をボード設定から取得 (Orin Nano Super では 0 番でない場合がある)
  info "電源モードを MAXN に設定..."
  MAXN_ID=$(grep -i "POWER_MODEL" /etc/nvpmodel.conf 2>/dev/null | grep -i "MAXN" | grep -o "ID=[0-9]*" | head -1 | cut -d= -f2 || echo "")
  MAXN_ID="${MAXN_ID:-0}"
  sudo nvpmodel -m "$MAXN_ID"
  ok "nvpmodel -m $MAXN_ID (MAXN) 適用"

  # クロック固定（ブースト維持）
  info "クロックを最大に固定..."
  sudo jetson_clocks
  ok "jetson_clocks 適用"

  # GPU メモリ空き確保
  info "メモリキャッシュをクリア..."
  echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
  ok "drop_caches 実行"

  # NvMap 設定（OOM対策）
  if ! grep -q "vm.min_free_kbytes" /etc/sysctl.d/60-nvmap.conf 2>/dev/null; then
    echo "vm.min_free_kbytes = 2097152" | sudo tee /etc/sysctl.d/60-nvmap.conf
    sudo sysctl -p /etc/sysctl.d/60-nvmap.conf
    ok "NvMap min_free_kbytes 設定"
  fi
else
  echo "  ℹ️  --apply フラグなし。設定はスキップします"
  echo "     実際に適用: bash setup/09_optimize_perf.sh --apply"
fi

echo ""

# ─── [3] 最適フラグの表示 ──────────────────────────────────────────────────────
head_ "── [3/5] 最適 llama-cli フラグ ──"
echo ""
cat << 'FLAGEOF'
  ⚡ 推奨フラグ（7 t/s → 40〜60 t/s）:

  重要度 ★★★  GPU オフロード:
    -ngl 999              # GPU ビルド時: 全レイヤーGPUオフロード（必須！）
    -ngl 0                # CPU 専用モード (libggml-cuda.so なし → 自動適用)

  重要度 ★★★  電源モード:
    sudo nvpmodel -m 0   # MAXN モード
    sudo jetson_clocks   # クロック固定

  重要度 ★★★  Jetson 統合メモリ対応 (Ollama Docker / llama-server):
    GGML_CUDA_NO_VMM=1   # Jetson は CUDA VMM 非対応のため必須
    OLLAMA_NUM_GPU=999   # 全レイヤー GPU オフロード (-ngl 999 相当)

  重要度 ★★   Flash Attention:
    --flash-attn          # メモリ使用量削減 + 高速化

  重要度 ★★   KV キャッシュ量子化:
    --cache-type-k q8_0  # KV キャッシュをq8に圧縮（メモリ節約）
    --cache-type-v q8_0

  重要度 ★    バッチ・スレッド:
    -b 512 -ub 512       # バッチサイズ
    -t 6                 # CPU スレッド数 (Orin Nano: 6コア)

  重要度 ★    コンテキストサイズ:
    -c 2048              # 不要に大きくしない（メモリ消費増）

FLAGEOF

# ─── [4] 最適化済み実行スクリプト生成 ──────────────────────────────────────────
head_ "── [4/5] 最適化済み実行スクリプト生成 ──"

OPTIMIZED_SCRIPT="$HOME/run_lfm_optimized.sh"

cat > "$OPTIMIZED_SCRIPT" << 'SCRIPTEOF'
#!/bin/bash
# LFM2.5-1.2B 最適化実行スクリプト
# Jetson Orin Nano Super 向け / 目標: 40〜60 t/s

MODEL_PATH="${1:-$HOME/.ollama/models/lfm25_gguf/LFM2.5-1.2B-Instruct-Q4_K_M.gguf}"
PROMPT="${2:-こんにちは！日本語でお話しできますか？}"

LLAMA_BIN="$HOME/llama.cpp/build/bin/llama-cli"
if [ ! -f "$LLAMA_BIN" ]; then
  echo "ERROR: llama-cli が見つかりません: $LLAMA_BIN"
  exit 1
fi
if [ ! -f "$MODEL_PATH" ]; then
  echo "ERROR: モデルが見つかりません: $MODEL_PATH"
  echo "使い方: $0 /path/to/model.gguf [prompt]"
  exit 1
fi

# クロック最大化（要sudo） — MAXN ID をボード設定から取得
MAXN_ID=$(grep -i "POWER_MODEL" /etc/nvpmodel.conf 2>/dev/null | grep -i "MAXN" | grep -o "ID=[0-9]*" | head -1 | cut -d= -f2 || echo "0")
sudo nvpmodel -m "${MAXN_ID:-0}" 2>/dev/null || true
sudo jetson_clocks 2>/dev/null || true
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

# CPU / GPU モード自動検出
LLAMA_BIN_DIR="$(dirname "$LLAMA_BIN")"
USE_GPU=false
if ls "$LLAMA_BIN_DIR"/libggml-cuda.so* >/dev/null 2>&1; then
  USE_GPU=true
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ⚡ LFM2.5-1.2B 最適化推論"
echo "  モデル: $(basename $MODEL_PATH)"
if $USE_GPU; then
  echo "  モード : GPU (-ngl 999) + Flash Attention"
else
  echo "  モード : CPU (-ngl 0) ← ~7 t/s"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ARGS=(
  -m "$MODEL_PATH"
  -c 2048
  -b 512 -ub 512
  -t 6
  -p "$PROMPT"
  -n 200
  --temp 0.7
  --repeat-penalty 1.1
)

if $USE_GPU; then
  export GGML_CUDA_FORCE_MMQ=1
  export GGML_CUDA_NO_PEER_COPY=1
  export CUDA_VISIBLE_DEVICES=0
  ARGS+=(-ngl 999 --flash-attn --cache-type-k q8_0 --cache-type-v q8_0)
fi

"$LLAMA_BIN" "${ARGS[@]}" 2>&1
SCRIPTEOF

chmod +x "$OPTIMIZED_SCRIPT"
ok "生成: $OPTIMIZED_SCRIPT"

# ─── [5] ベンチマーク比較用コマンド ────────────────────────────────────────────
head_ "── [5/5] 速度確認コマンド ──"
echo ""
cat << 'BENCHEOF'
  # GPU使用確認（別ターミナルで実行）:
  watch -n 0.5 nvidia-smi

  # 最適化前 vs 後 の比較:
  # Before: llama-cli -m model.gguf -p "test" -n 100
  # After:  ~/run_lfm_optimized.sh /path/to/model.gguf "test prompt"

  # t/s だけ確認:
  llama-cli -m model.gguf -ngl 999 --flash-attn -p "hello" -n 100 2>&1 | grep "tok/s"

BENCHEOF

echo ""
echo "══════════════════════════════════════════════════════"
ok "最適化チェック完了"
if ! $APPLY; then
  echo ""
  echo -e "${YELLOW}  → 設定を適用するには:${NC}"
  echo "     bash setup/09_optimize_perf.sh --apply"
fi
echo "══════════════════════════════════════════════════════"
echo ""
