#!/bin/bash
# setup/06_setup_lfm.sh - LFM-2.5 セットアップ
#
# 戦略:
#   1. まず Ollama 公式の lfm2.5-thinking を試す (1.2B, ~0.7GB)
#   2. 次に コミュニティ版 hadad/LFM2.5-1.2B を試す
#   3. 失敗した場合は HuggingFace GGUF からインポートする
#
# LFM-2.5 は SSM (State Space Model) + Attention ハイブリッドで
# Transformer より省メモリ。Jetson 8GB に向いている。

set -e

OLLAMA_API="http://localhost:11434"
GGUF_DIR="$HOME/.ollama/lfm25_gguf"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

# ─── ヘルパー関数 ──────────────────────────────────────────────────────────────

_install_thinking() {
  echo ""
  info "lfm2.5-thinking を pull 中 (~0.7GB)..."
  if ollama pull lfm2.5-thinking; then
    ok "lfm2.5-thinking インストール完了"
    echo "  テスト: ollama run lfm2.5-thinking '1+1は何ですか？'"
  else
    err "lfm2.5-thinking の pull に失敗しました → GGUF インポートを試してください"
    return 1
  fi
}

_install_instruct() {
  echo ""
  info "hadad/LFM2.5-1.2B:Q4_K_M を pull 中 (~0.7GB)..."
  if ollama pull "hadad/LFM2.5-1.2B:Q4_K_M"; then
    ok "hadad/LFM2.5-1.2B インストール完了"
    echo "  テスト: ollama run hadad/LFM2.5-1.2B:Q4_K_M 'こんにちは'"
  else
    err "hadad/LFM2.5-1.2B の pull に失敗しました"
    return 1
  fi
}

_install_gguf() {
  echo ""
  echo "── GGUF インポート (LiquidAI/LFM2.5-1.2B-Instruct-GGUF) ──"

  # huggingface_hub チェック
  if ! python3 -c "import huggingface_hub" 2>/dev/null; then
    info "huggingface_hub をインストール中..."
    pip3 install -q huggingface_hub
  fi

  mkdir -p "$GGUF_DIR"
  info "GGUF をダウンロード中 (LiquidAI 公式 Q4_K_M ~0.7GB)..."

  python3 - <<PYEOF
from huggingface_hub import hf_hub_download
import os
save_dir = os.path.expanduser("~/.ollama/lfm25_gguf")
hf_hub_download(
    repo_id="LiquidAI/LFM2.5-1.2B-Instruct-GGUF",
    filename="LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
    local_dir=save_dir,
)
print("  ダウンロード完了")
PYEOF

  local gguf_file="$GGUF_DIR/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
  if [ ! -f "$gguf_file" ]; then
    err "GGUF ファイルが見つかりません: $gguf_file"
    return 1
  fi
  ok "GGUF ダウンロード完了"

  # Modelfile 作成
  cat > "$GGUF_DIR/Modelfile" <<EOF
FROM $gguf_file

SYSTEM """You are a helpful assistant. Please respond in the same language as the user."""

TEMPLATE """<|im_start|>system
{{ .System }}<|im_end|>
<|im_start|>user
{{ .Prompt }}<|im_end|>
<|im_start|>assistant
"""

PARAMETER stop "<|im_end|>"
PARAMETER num_ctx 4096
PARAMETER temperature 0.2
EOF

  info "Ollama にインポート中 (モデル名: lfm2.5-local)..."
  ollama create lfm2.5-local -f "$GGUF_DIR/Modelfile"
  ok "lfm2.5-local としてインポート完了"
  echo "  テスト: ollama run lfm2.5-local 'こんにちは'"
}

# ─── メイン ───────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════"
echo "  LFM-2.5 セットアップ"
echo "══════════════════════════════════════════════"
echo ""
echo "  LFM-2.5 (Liquid Foundation Model) は"
echo "  SSM + Attention ハイブリッドで Transformer より省メモリ。"
echo "  1.2B パラメータで ~0.7GB。Jetson に最適。"
echo ""

# Ollama API チェック
if ! curl -s "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
  err "Ollama API が応答しません"
  echo "  先に Ollama を起動してください: sudo docker start ollama"
  exit 1
fi
ok "Ollama API 確認"

echo ""
echo "インストールするモデルを選択:"
echo "  1) lfm2.5-thinking    - 推論特化・Ollama公式 (~0.7GB) [推奨]"
echo "  2) hadad/LFM2.5-1.2B  - 汎用 Instruct・コミュニティ (~0.7GB)"
echo "  3) GGUF 手動インポート  - LiquidAI HuggingFace から直接取得"
echo "  4) 1 + 2 両方インストール"
echo ""
read -r -p "選択 [1-4]: " choice

case "$choice" in
  1) _install_thinking ;;
  2) _install_instruct ;;
  3) _install_gguf ;;
  4) _install_thinking || true; _install_instruct || true ;;
  *) err "無効な選択です"; exit 1 ;;
esac

echo ""
echo "══════════════════════════════════════════════"
ok "LFM-2.5 セットアップ完了"
echo "══════════════════════════════════════════════"
echo ""
echo "  インストール済み LFM モデル:"
ollama list 2>/dev/null | grep -iE "lfm" || echo "    (なし - エラーが発生した可能性があります)"
echo ""
echo "  ヒント: LFM-2.5 は temperature 0.1〜0.2 が推奨"
echo ""
