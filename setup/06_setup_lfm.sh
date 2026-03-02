#!/bin/bash
# setup/06_setup_lfm.sh - LFM-2.5 セットアップ
#
# dustynv/ollama:r36.4.0 の Ollama バージョンが古いため
# ollama pull は 412/500 で失敗する。
# HuggingFace GGUF → ollama create で直接インポートする。

OLLAMA_API="http://localhost:11434"
GGUF_DIR="$HOME/.ollama/lfm25_gguf"
GGUF_FILE="$GGUF_DIR/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
MODEL_NAME="lfm2.5-local"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

echo ""
echo "══════════════════════════════════════════════"
echo "  LFM-2.5 セットアップ (GGUF インポート)"
echo "══════════════════════════════════════════════"
echo ""
echo "  LiquidAI/LFM2.5-1.2B-Instruct-GGUF (Q4_K_M ~0.7GB)"
echo "  を HuggingFace からダウンロードして ollama にインポートします。"
echo ""

# ─── Ollama API チェック ──────────────────────────────────────────────────────
if ! curl -s "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
  err "Ollama API が応答しません"
  echo "  先に起動してください: sudo docker start ollama"
  exit 1
fi
ok "Ollama API 確認"

# ─── 既にインポート済みか確認 ────────────────────────────────────────────────
if ollama list 2>/dev/null | grep -q "^$MODEL_NAME"; then
  ok "$MODEL_NAME は既にインポート済みです"
  echo ""
  echo "  テスト: ollama run $MODEL_NAME 'こんにちは'"
  echo ""
  exit 0
fi

# ─── huggingface_hub ─────────────────────────────────────────────────────────
echo ""
echo "── [1/3] huggingface_hub 確認 ──"
if ! python3 -c "import huggingface_hub" 2>/dev/null; then
  info "huggingface_hub をインストール中..."
  pip3 install -q huggingface_hub
fi
ok "huggingface_hub 利用可能"

# ─── GGUF ダウンロード ────────────────────────────────────────────────────────
echo ""
echo "── [2/3] GGUF ダウンロード ──"
mkdir -p "$GGUF_DIR"

if [ -f "$GGUF_FILE" ]; then
  ok "キャッシュ済み: $GGUF_FILE"
else
  info "ダウンロード中 (~0.7GB、しばらくかかります)..."
  python3 - <<PYEOF
from huggingface_hub import hf_hub_download
import os, sys

save_dir = os.path.expanduser("~/.ollama/lfm25_gguf")
try:
    path = hf_hub_download(
        repo_id="LiquidAI/LFM2.5-1.2B-Instruct-GGUF",
        filename="LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
        local_dir=save_dir,
    )
    print(f"  保存先: {path}")
except Exception as e:
    print(f"エラー: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

  if [ ! -f "$GGUF_FILE" ]; then
    err "ダウンロードに失敗しました"
    exit 1
  fi
  ok "ダウンロード完了: $GGUF_FILE"
fi

# ─── Modelfile 作成 & ollama create ─────────────────────────────────────────
echo ""
echo "── [3/3] Ollama にインポート ──"

cat > "$GGUF_DIR/Modelfile" <<EOF
FROM $GGUF_FILE

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

info "ollama create $MODEL_NAME ..."
if ollama create "$MODEL_NAME" -f "$GGUF_DIR/Modelfile"; then
  ok "インポート完了"
else
  err "ollama create に失敗しました"
  exit 1
fi

# ─── 完了 ────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
ok "セットアップ完了: $MODEL_NAME"
echo "══════════════════════════════════════════════"
echo ""
echo "  テスト実行:"
echo "    ollama run $MODEL_NAME 'こんにちは'"
echo ""
echo "  ヒント: temperature 0.1〜0.2 推奨 (deterministic な設計)"
echo ""
