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
if [[ "$CURRENT_POWER" != "MAXN" ]]; then
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
  # CUDA サポート確認
  if "$LLAMA_BIN" --version 2>&1 | grep -qi "CUDA\|cuda"; then
    ok "llama-cli: CUDA ビルド確認済み"
  else
    # バイナリの CUDA リンクを確認
    if ldd "$LLAMA_BIN" 2>/dev/null | grep -qi "libcuda\|libcublas"; then
      ok "llama-cli: CUDA リンク確認済み"
    else
      err "llama-cli: CUDAリンクなし → CPU専用ビルドの可能性"
      echo "  → bash setup/05_setup_llamacpp.sh を再実行してください"
    fi
  fi
else
  err "llama-cli が見つかりません → bash setup/05_setup_llamacpp.sh を実行してください"
fi

echo ""

# ─── [2] 設定適用 ──────────────────────────────────────────────────────────────
head_ "── [2/5] 電源・クロック最適化 ──"

if $APPLY; then
  # MAXN モード（最大パフォーマンス）
  info "電源モードを MAXN に設定..."
  sudo nvpmodel -m 0
  ok "nvpmodel -m 0 (MAXN) 適用"

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

  重要度 ★★★  GPU オフロード (これがないとCPU推論になる):
    -ngl 999              # 全レイヤーをGPUに乗せる（必須！）

  重要度 ★★★  電源モード:
    sudo nvpmodel -m 0   # MAXN モード
    sudo jetson_clocks   # クロック固定

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

# クロック最大化（要sudo）
sudo nvpmodel -m 0 2>/dev/null || true
sudo jetson_clocks 2>/dev/null || true
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ⚡ LFM2.5-1.2B 最適化推論"
echo "  モデル: $(basename $MODEL_PATH)"
echo "  GPU layers: ALL (-ngl 999)"
echo "  Flash Attention: ON"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

"$LLAMA_BIN" \
  -m "$MODEL_PATH" \
  -ngl 999 \
  --flash-attn \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  -c 2048 \
  -b 512 -ub 512 \
  -t 6 \
  -p "$PROMPT" \
  -n 200 \
  --temp 0.7 \
  --repeat-penalty 1.1 \
  2>&1
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
