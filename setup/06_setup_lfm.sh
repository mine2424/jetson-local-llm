#!/bin/bash
# setup/06_setup_lfm.sh - LFM-2.5 セットアップ
#
# dustynv/ollama コンテナ内の Ollama バージョンが古い場合、
# lfm2.5-thinking などの新しいモデルは 412 エラーで pull できない。
# そのため Ollama pull → 失敗時に GGUF インポートへ自動フォールバックする。

OLLAMA_API="http://localhost:11434"
GGUF_DIR="$HOME/.ollama/lfm25_gguf"
GGUF_FILE="$GGUF_DIR/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
MODEL_NAME="lfm2.5-local"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

# ─── GGUF インポート ──────────────────────────────────────────────────────────

_install_gguf() {
  echo ""
  echo "── GGUF インポート (LiquidAI 公式 Q4_K_M ~0.7GB) ──"

  # huggingface_hub チェック
  if ! python3 -c "import huggingface_hub" 2>/dev/null; then
    info "huggingface_hub をインストール中..."
    pip3 install -q huggingface_hub
  fi

  mkdir -p "$GGUF_DIR"

  # ダウンロード済みならスキップ
  if [ -f "$GGUF_FILE" ]; then
    ok "GGUF キャッシュ済み: $GGUF_FILE"
  else
    info "HuggingFace からダウンロード中..."
    python3 - <<PYEOF
from huggingface_hub import hf_hub_download
import os
hf_hub_download(
    repo_id="LiquidAI/LFM2.5-1.2B-Instruct-GGUF",
    filename="LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
    local_dir=os.path.expanduser("~/.ollama/lfm25_gguf"),
)
PYEOF

    if [ ! -f "$GGUF_FILE" ]; then
      err "ダウンロードに失敗しました"
      return 1
    fi
    ok "ダウンロード完了"
  fi

  # Modelfile 作成
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

  info "Ollama にインポート中 (モデル名: $MODEL_NAME)..."
  if ollama create "$MODEL_NAME" -f "$GGUF_DIR/Modelfile"; then
    ok "$MODEL_NAME としてインポート完了"
    echo "  テスト: ollama run $MODEL_NAME 'こんにちは'"
    return 0
  else
    err "ollama create に失敗しました"
    return 1
  fi
}

# ─── Ollama pull (フォールバック付き) ────────────────────────────────────────

_try_pull() {
  local model="$1"
  info "ollama pull $model を試行中..."
  if ollama pull "$model" 2>&1; then
    ok "$model インストール完了"
    return 0
  else
    err "pull 失敗 (コンテナ内 Ollama が古い可能性があります)"
    return 1
  fi
}

# ─── メイン ───────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════"
echo "  LFM-2.5 セットアップ"
echo "══════════════════════════════════════════════"
echo ""
echo "  LFM-2.5 (Liquid Foundation Model)"
echo "  SSM + Attention ハイブリッド / 1.2B / ~0.7GB"
echo "  Transformer より省メモリ。Jetson に最適。"
echo ""

# Ollama API チェック
if ! curl -s "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
  err "Ollama API が応答しません"
  echo "  先に起動してください: sudo docker start ollama"
  exit 1
fi
ok "Ollama API 確認"

# Ollama バージョン確認
OLLAMA_VER=$(ollama --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "不明")
info "Ollama バージョン: $OLLAMA_VER"

echo ""
echo "── [1/2] Ollama pull を試みます ──"
echo "   (コンテナ内バージョンが古い場合は自動的に GGUF に切り替えます)"
echo ""

PULL_SUCCESS=false

# lfm2.5-thinking を試す
if _try_pull "lfm2.5-thinking"; then
  PULL_SUCCESS=true
  INSTALLED_MODEL="lfm2.5-thinking"
else
  echo ""
  info "hadad/LFM2.5-1.2B:Q4_K_M を試みます..."
  if _try_pull "hadad/LFM2.5-1.2B:Q4_K_M"; then
    PULL_SUCCESS=true
    INSTALLED_MODEL="hadad/LFM2.5-1.2B:Q4_K_M"
  fi
fi

if [ "$PULL_SUCCESS" = false ]; then
  echo ""
  echo "── [2/2] GGUF インポートにフォールバック ──"
  echo "   LiquidAI/LFM2.5-1.2B-Instruct-GGUF (HuggingFace 公式) を使用します"
  echo ""
  if _install_gguf; then
    INSTALLED_MODEL="$MODEL_NAME"
  else
    err "すべての方法が失敗しました"
    exit 1
  fi
fi

echo ""
echo "══════════════════════════════════════════════"
ok "セットアップ完了: $INSTALLED_MODEL"
echo "══════════════════════════════════════════════"
echo ""
echo "  インストール済み LFM モデル:"
ollama list 2>/dev/null | grep -iE "lfm" || echo "    (なし)"
echo ""
echo "  テスト実行:"
echo "    ollama run $INSTALLED_MODEL 'こんにちは'"
echo ""
echo "  ヒント: temperature 0.1〜0.2 が推奨 (deterministic な設計)"
echo ""
