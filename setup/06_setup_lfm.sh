#!/bin/bash
# setup/06_setup_lfm.sh - LFM-2.5 セットアップ
#
# dustynv/ollama コンテナの Ollama バージョンが古いため
# ollama pull は 412/500 で失敗する。
# HuggingFace GGUF → Ollama API /api/create で直接インポートする。
#
# マウントパス: ~/.ollama/models → /data/models/ollama/models (コンテナ内)

set -e

OLLAMA_API="http://localhost:11434"
# マウントパス内に保存: コンテナからアクセス可能
GGUF_DIR="$HOME/.ollama/models/lfm25_gguf"
GGUF_FILE="$GGUF_DIR/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
# コンテナ内から見えるパス
CONTAINER_GGUF="/data/models/ollama/models/lfm25_gguf/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
MODEL_NAME="lfm2.5-local"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

# ─── Ollama バイナリをコンテナ内でアップグレード ─────────────────────────────
_upgrade_ollama_in_container() {
  local current_ver
  current_ver=$(sudo docker exec ollama ollama --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0.0.0")

  local latest_url="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-arm64"
  local tmp_bin="/tmp/ollama_new"

  info "Ollama バイナリをアップグレード中 (現在: $current_ver)..."
  if ! curl -fsSL -o "$tmp_bin" "$latest_url"; then
    err "バイナリのダウンロードに失敗しました (ネット接続を確認してください)"
    return 1
  fi
  chmod +x "$tmp_bin"

  local bin_path
  bin_path=$(sudo docker exec ollama which ollama 2>/dev/null || echo "/usr/bin/ollama")

  sudo docker cp "$tmp_bin" "ollama:${bin_path}"
  rm -f "$tmp_bin"
  ok "バイナリをコンテナにコピーしました"

  info "コンテナを再起動中..."
  sudo docker restart ollama > /dev/null

  # API が応答するまで最大 30 秒待機
  local i=0
  while [ $i -lt 30 ]; do
    if curl -s "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
      local new_ver
      new_ver=$(sudo docker exec ollama ollama --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
      ok "Ollama アップグレード完了: $current_ver → $new_ver"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done

  err "コンテナ再起動後に API が応答しませんでした"
  return 1
}

# ─── 実行中モデルのアンロード + GPU メモリ解放 (API経由) ─────────────────────
_unload_models() {
  local running
  running=$(curl -s "$OLLAMA_API/api/ps" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    for m in json.load(sys.stdin).get('models', []):
        print(m['name'])
except:
    pass
" 2>/dev/null || true)

  for m in $running; do
    info "モデルをアンロード: $m"
    # keep_alive=0 でモデルをアンロード
    curl -s -X POST "$OLLAMA_API/api/generate" \
      -H "Content-Type: application/json" \
      -d "{\"model\": \"$m\", \"keep_alive\": 0}" > /dev/null 2>&1 || true
  done
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
}

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

# ─── 既にインポート済みか確認 (API経由) ──────────────────────────────────────
already_imported=$(curl -s "$OLLAMA_API/api/tags" | \
  python3 -c "
import sys, json
try:
    models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
    print('yes' if '$MODEL_NAME' in models else 'no')
except:
    print('no')
" 2>/dev/null || echo "no")

if [ "$already_imported" = "yes" ]; then
  ok "$MODEL_NAME は既にインポート済みです"
  echo ""
  echo "  テスト (API経由):"
  echo "    curl -s -X POST $OLLAMA_API/api/generate \\"
  echo "      -d '{\"model\": \"$MODEL_NAME\", \"prompt\": \"こんにちは\", \"stream\": false}' | python3 -m json.tool"
  echo ""
  exit 0
fi

# ─── huggingface_hub ─────────────────────────────────────────────────────────
echo ""
echo "── [1/4] huggingface_hub 確認 ──"
if ! python3 -c "import huggingface_hub" 2>/dev/null; then
  info "huggingface_hub をインストール中..."
  pip3 install -q huggingface_hub
fi
ok "huggingface_hub 利用可能"

# ─── GGUF ダウンロード (マウントパス内へ) ─────────────────────────────────────
echo ""
echo "── [2/4] GGUF ダウンロード ──"
echo "  保存先: $GGUF_DIR (コンテナマウントパス内)"
mkdir -p "$GGUF_DIR"

if [ -f "$GGUF_FILE" ]; then
  ok "キャッシュ済み: $GGUF_FILE"
else
  info "ダウンロード中 (~0.7GB、しばらくかかります)..."
  python3 - <<PYEOF
from huggingface_hub import hf_hub_download
import os, sys

save_dir = "$GGUF_DIR"
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

# ─── Ollama バイナリをアップグレード ─────────────────────────────────────────
echo ""
echo "── [3/4] Ollama バイナリをアップグレード ──"
if ! _upgrade_ollama_in_container; then
  err "Ollama のアップグレードに失敗しました。既存バージョンで続行します..."
fi

# ─── Modelfile 作成 & API /api/create ────────────────────────────────────────
echo ""
echo "── [4/4] Ollama にインポート (API /api/create) ──"
_unload_models

# Modelfile 内容 (コンテナ内パスを使用)
cat > "$GGUF_DIR/Modelfile" <<EOF
FROM $CONTAINER_GGUF

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

info "API /api/create でインポート中 ($MODEL_NAME)..."
response=$(python3 - <<PYEOF
import json, subprocess, sys

with open("$GGUF_DIR/Modelfile") as f:
    modelfile = f.read()

payload = json.dumps({
    "name": "$MODEL_NAME",
    "modelfile": modelfile,
    "stream": False
})

result = subprocess.run(
    ["curl", "-s", "-X", "POST", "$OLLAMA_API/api/create",
     "-H", "Content-Type: application/json",
     "-d", payload],
    capture_output=True, text=True
)
print(result.stdout)
PYEOF
)

status=$(echo "$response" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print(d.get('status', 'error'))
except:
    print('error')
" 2>/dev/null || echo "error")

if [ "$status" = "success" ]; then
  ok "インポート完了: $MODEL_NAME"
else
  err "ollama create に失敗しました"
  err "レスポンス: $response"
  exit 1
fi

# ─── 完了 ────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
ok "セットアップ完了: $MODEL_NAME"
echo "══════════════════════════════════════════════"
echo ""
echo "  テスト実行 (API経由):"
echo "    curl -s -X POST $OLLAMA_API/api/generate \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"model\": \"$MODEL_NAME\", \"prompt\": \"こんにちは\", \"stream\": false}' \\"
echo "      | python3 -m json.tool"
echo ""
echo "  ヒント: temperature 0.1〜0.2 推奨 (deterministic な設計)"
echo ""
