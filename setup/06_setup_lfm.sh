#!/bin/bash
# setup/06_setup_lfm.sh - LFM-2.5 セットアップ
#
# 戦略:
#   [1] Ollama バイナリをコンテナ内でアップグレード
#       (dustynv/ollama の古いバージョンは lfm2.5-thinking pull が 412/500 で失敗)
#   [2] Ollama API で lfm2.5-thinking:1.2b-q4_K_M を pull
#   [3] pull 失敗時のフォールバック:
#       HuggingFace GGUF → Ollama API /api/create でインポート
#
# マウントパス: ~/.ollama/models → /data/models/ollama/models (コンテナ内)

set -e

OLLAMA_API="http://localhost:11434"
# Ollama公式モデル名
OFFICIAL_MODEL="lfm2.5-thinking:1.2b-q4_K_M"
# GGUF フォールバック用パス
GGUF_DIR="$HOME/.ollama/models/lfm25_gguf"
GGUF_FILE="$GGUF_DIR/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
CONTAINER_GGUF="/data/models/ollama/models/lfm25_gguf/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
GGUF_MODEL_NAME="lfm2.5-local"

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
echo "══════════════════════════════════════════════════════"
echo "  LFM-2.5 セットアップ"
echo "  [1] バイナリアップグレード → [2] API pull → [3] GGUF フォールバック"
echo "══════════════════════════════════════════════════════"
echo ""

# ─── Ollama API チェック ──────────────────────────────────────────────────────
if ! curl -s "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
  err "Ollama API が応答しません"
  echo "  先に起動してください: sudo docker start ollama"
  exit 1
fi
ok "Ollama API 確認"

# ─── 既にインストール済みか確認 ──────────────────────────────────────────────
_is_installed() {
  local name="$1"
  curl -s "$OLLAMA_API/api/tags" | \
    python3 -c "
import sys, json
models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
print('yes' if '$name' in models or any(m.startswith('$name'.split(':')[0]) for m in models) else 'no')
" 2>/dev/null || echo "no"
}

# 公式モデル or GGUF版どちらかが入っていれば済み
already=$(curl -s "$OLLAMA_API/api/tags" | python3 -c "
import sys, json
models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
found = [m for m in models if 'lfm2.5' in m.lower()]
print('yes' if found else 'no')
print('\n'.join(found))
" 2>/dev/null | head -1 || echo "no")

if [ "$already" = "yes" ]; then
  ok "LFM-2.5 は既にインストール済みです"
  curl -s "$OLLAMA_API/api/tags" | python3 -c "
import sys, json
for m in json.load(sys.stdin).get('models', []):
    if 'lfm2.5' in m['name'].lower():
        print(f'  • {m[\"name\"]}')
" 2>/dev/null
  echo ""
  echo "  使用例: curl -s -X POST $OLLAMA_API/api/generate \\"
  echo "    -d '{\"model\": \"$OFFICIAL_MODEL\", \"prompt\": \"こんにちは\", \"stream\": false}'"
  echo ""
  exit 0
fi

# ─── [1/3] Ollama バイナリをアップグレード ────────────────────────────────────
echo ""
echo "── [1/3] Ollama バイナリをアップグレード ──"
echo "  (dustynv/ollama の古いバージョンでは LFM-2.5 pull が 412/500 で失敗するため)"
if ! _upgrade_ollama_in_container; then
  info "アップグレード失敗。既存バージョンで続行します..."
fi

# ─── [2/3] Ollama API pull を試みる ──────────────────────────────────────────
echo ""
echo "── [2/3] Ollama API pull: $OFFICIAL_MODEL ──"
_unload_models
info "pull中... (~731MB、しばらくかかります)"

pull_status=$(curl -s -X POST "$OLLAMA_API/api/pull" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$OFFICIAL_MODEL\"}" \
  2>/dev/null | python3 -c "
import sys, json
last = ''
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        s = d.get('status', '')
        if 'total' in d and d['total'] > 0:
            pct = int(d.get('completed', 0) / d['total'] * 100)
            print(f'\r  {s}: {pct}%', end='', flush=True)
        elif s:
            print(f'  {s}')
        last = 'error' if 'error' in d else s
    except: pass
print()
print(last)
" 2>/dev/null | tail -1 || echo "error")

if [ "$pull_status" = "success" ]; then
  ok "API pull 成功: $OFFICIAL_MODEL"
  echo ""
  echo "══════════════════════════════════════════════════════"
  ok "セットアップ完了 (Ollama公式モデル)"
  echo "══════════════════════════════════════════════════════"
  echo ""
  echo "  モデル名: $OFFICIAL_MODEL"
  echo "  125K コンテキスト対応"
  echo ""
  echo "  テスト: curl -s -X POST $OLLAMA_API/api/generate \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"model\": \"$OFFICIAL_MODEL\", \"prompt\": \"こんにちは\", \"stream\": false}' \\"
  echo "    | python3 -c \"import sys,json; print(json.load(sys.stdin)['response'])\""
  echo ""
  echo "  インタラクティブ: ./ollama-run.sh $OFFICIAL_MODEL"
  echo ""
  exit 0
fi

# ─── [3/3] GGUF フォールバック ────────────────────────────────────────────────
echo ""
info "API pull に失敗しました。GGUF フォールバックに切り替えます..."
echo ""
echo "── [3/3] GGUF ダウンロード → /api/create インポート ──"
echo "  (HuggingFace: LiquidAI/LFM2.5-1.2B-Instruct-GGUF Q4_K_M ~0.7GB)"

# huggingface_hub チェック
if ! python3 -c "import huggingface_hub" 2>/dev/null; then
  info "huggingface_hub をインストール中..."
  pip3 install -q huggingface_hub
fi

mkdir -p "$GGUF_DIR"

if [ -f "$GGUF_FILE" ]; then
  ok "キャッシュ済み: $GGUF_FILE"
else
  info "ダウンロード中..."
  python3 - <<PYEOF
from huggingface_hub import hf_hub_download
import sys
try:
    path = hf_hub_download(
        repo_id="LiquidAI/LFM2.5-1.2B-Instruct-GGUF",
        filename="LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
        local_dir="$GGUF_DIR",
    )
    print(f"  保存先: {path}")
except Exception as e:
    print(f"エラー: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
  [ ! -f "$GGUF_FILE" ] && { err "ダウンロードに失敗しました"; exit 1; }
  ok "ダウンロード完了"
fi

_unload_models

# Modelfile → /api/create
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

info "API /api/create でインポート中 ($GGUF_MODEL_NAME)..."
response=$(python3 - <<PYEOF
import json, subprocess
with open("$GGUF_DIR/Modelfile") as f:
    modelfile = f.read()
payload = json.dumps({"name": "$GGUF_MODEL_NAME", "modelfile": modelfile, "stream": False})
result = subprocess.run(
    ["curl", "-s", "-X", "POST", "$OLLAMA_API/api/create",
     "-H", "Content-Type: application/json", "-d", payload],
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
  ok "インポート完了: $GGUF_MODEL_NAME"
else
  err "GGUF インポートに失敗しました"
  err "レスポンス: $response"
  exit 1
fi

echo ""
echo "══════════════════════════════════════════════════════"
ok "セットアップ完了 (GGUF インポート)"
echo "══════════════════════════════════════════════════════"
echo ""
echo "  モデル名: $GGUF_MODEL_NAME"
echo "  ※ Ollama公式版 ($OFFICIAL_MODEL) とは別名で登録されています"
echo ""
echo "  テスト: curl -s -X POST $OLLAMA_API/api/generate \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\": \"$GGUF_MODEL_NAME\", \"prompt\": \"こんにちは\", \"stream\": false}' \\"
echo "    | python3 -c \"import sys,json; print(json.load(sys.stdin)['response'])\""
echo ""
echo "  ヒント: temperature 0.1〜0.2 推奨 (deterministic な設計)"
echo ""
