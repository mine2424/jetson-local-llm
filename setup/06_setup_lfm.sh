#!/bin/bash
# setup/06_setup_lfm.sh - LFM-2.5 セットアップ
#
# 戦略 (Liquid AI 公式: llama.cpp を day-0 サポート):
#   [1] Ollama バイナリをコンテナ内でアップグレード
#   [2] Ollama API pull: lfm2.5-thinking:1.2b-q4_K_M
#       → 成功: Ollama (port 11434) で提供
#   [3] fallback: llama.cpp (llama-server) で提供
#       - HuggingFace GGUF を直接ダウンロード
#       - llama-server を port 8081 で起動 (OpenAI互換)
#       - 日本語モデル: LiquidAI/LFM2.5-1.2B-JP-GGUF
#
# マウントパス: ~/.ollama/models → /data/models/ollama/models (コンテナ内)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLLAMA_API="http://localhost:11434"
LLAMACPP_SERVER_PORT=8081
LLAMACPP_DIR="$HOME/llama.cpp"
LLAMACPP_BIN="$LLAMACPP_DIR/build/bin"
GGUF_DIR="$HOME/.ollama/models/lfm25_gguf"
OFFICIAL_MODEL="lfm2.5-thinking:1.2b-q4_K_M"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

# ─── Ollama バイナリをコンテナ内でアップグレード ─────────────────────────────
_upgrade_ollama_in_container() {
  local current_ver
  current_ver=$(sudo docker exec ollama ollama --version 2>/dev/null \
    | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0.0.0")

  local tmp_bin="/tmp/ollama_new"
  info "Ollama バイナリをアップグレード中 (現在: $current_ver)..."
  if ! curl -fsSL -o "$tmp_bin" \
      "https://github.com/ollama/ollama/releases/latest/download/ollama-linux-arm64"; then
    err "バイナリのダウンロードに失敗しました"
    return 1
  fi
  chmod +x "$tmp_bin"

  local bin_path
  bin_path=$(sudo docker exec ollama which ollama 2>/dev/null || echo "/usr/bin/ollama")
  sudo docker cp "$tmp_bin" "ollama:${bin_path}"
  rm -f "$tmp_bin"

  info "コンテナを再起動中..."
  sudo docker restart ollama > /dev/null

  for i in $(seq 1 30); do
    if curl -s "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
      local new_ver
      new_ver=$(sudo docker exec ollama ollama --version 2>/dev/null \
        | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
      ok "Ollama アップグレード完了: $current_ver → $new_ver"
      return 0
    fi
    sleep 1
  done
  err "再起動後に API が応答しませんでした"
  return 1
}

# ─── ロード中モデルをアンロード ───────────────────────────────────────────────
_unload_models() {
  local running
  running=$(curl -s "$OLLAMA_API/api/ps" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    for m in json.load(sys.stdin).get('models', []):
        print(m['name'])
except: pass
" 2>/dev/null || true)
  for m in $running; do
    curl -s -X POST "$OLLAMA_API/api/generate" \
      -H "Content-Type: application/json" \
      -d "{\"model\": \"$m\", \"keep_alive\": 0}" > /dev/null 2>&1 || true
  done
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
}

# ─── llama.cpp が使える状態か確認 ───────────────────────────────────────────
_check_llamacpp() {
  [ -f "$LLAMACPP_BIN/llama-server" ]
}

# ─── llama-server で LFM-2.5 を起動 ─────────────────────────────────────────
_start_llamacpp_server() {
  local gguf_path="$1"
  local model_label="$2"

  # 既存プロセスを停止
  pkill -f "llama-server.*$LLAMACPP_SERVER_PORT" 2>/dev/null || true
  sleep 1

  # NvMap 用にキャッシュ解放
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true

  info "llama-server 起動中 (port $LLAMACPP_SERVER_PORT)..."
  info "モデル: $gguf_path"

  nohup "$LLAMACPP_BIN/llama-server" \
    -m "$gguf_path" \
    -ngl 99 \
    -c 4096 \
    --host 0.0.0.0 \
    --port "$LLAMACPP_SERVER_PORT" \
    --log-disable \
    > /tmp/llama-server.log 2>&1 &

  echo $! > /tmp/llama-server.pid

  # 起動待機 (最大20秒)
  for i in $(seq 1 20); do
    if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
      ok "llama-server 起動完了 (port $LLAMACPP_SERVER_PORT)"
      return 0
    fi
    sleep 1
  done

  err "llama-server が起動しませんでした"
  err "ログ: cat /tmp/llama-server.log"
  return 1
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "══════════════════════════════════════════════════════"
echo "  LFM-2.5 セットアップ"
echo "  [1] Ollama 試行 → [2] llama.cpp fallback"
echo "══════════════════════════════════════════════════════"
echo ""

# ─── Ollama API チェック ──────────────────────────────────────────────────────
if ! curl -s "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
  err "Ollama API が応答しません"
  echo "  sudo docker start ollama"
  exit 1
fi
ok "Ollama API 確認"

# ─── 既にインストール済み？ ───────────────────────────────────────────────────
already=$(curl -s "$OLLAMA_API/api/tags" | python3 -c "
import sys, json
models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
found = [m for m in models if 'lfm2.5' in m.lower()]
print('yes' if found else 'no')
" 2>/dev/null || echo "no")

if [ "$already" = "yes" ]; then
  ok "LFM-2.5 は既に Ollama にインストール済みです"
  curl -s "$OLLAMA_API/api/tags" | python3 -c "
import sys, json
for m in json.load(sys.stdin).get('models', []):
    if 'lfm2.5' in m['name'].lower():
        print(f'  • {m[\"name\"]}')
" 2>/dev/null
  exit 0
fi

# llama-server が既に動いているか確認
if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
  ok "llama-server が既に port $LLAMACPP_SERVER_PORT で動作中"
  exit 0
fi

# ─── [1/2] Ollama ルート ──────────────────────────────────────────────────────
echo ""
echo "━━ [1/2] Ollama API pull を試みます ━━"

echo "── Ollama バイナリをアップグレード ──"
if ! _upgrade_ollama_in_container; then
  info "アップグレード失敗。既存バージョンで続行..."
fi

_unload_models

info "pull 中: $OFFICIAL_MODEL (~731MB)"
pull_status=$(curl -s -X POST "$OLLAMA_API/api/pull" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$OFFICIAL_MODEL\"}" 2>/dev/null | python3 -c "
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
  ok "Ollama API pull 成功: $OFFICIAL_MODEL"
  echo ""
  echo "══════════════════════════════════════════════════════"
  ok "完了: Ollama (port 11434) で利用可能"
  echo "══════════════════════════════════════════════════════"
  echo ""
  echo "  テスト:"
  echo "    curl -s -X POST $OLLAMA_API/api/generate \\"
  echo "      -d '{\"model\": \"$OFFICIAL_MODEL\", \"prompt\": \"こんにちは\", \"stream\": false}' \\"
  echo "      | python3 -c \"import sys,json; print(json.load(sys.stdin)['response'])\""
  echo ""
  echo "  インタラクティブ: ./ollama-run.sh $OFFICIAL_MODEL"
  echo ""
  exit 0
fi

# ─── [2/2] llama.cpp fallback ────────────────────────────────────────────────
echo ""
info "Ollama pull に失敗しました。llama.cpp fallback に切り替えます。"
echo ""
echo "━━ [2/2] llama.cpp fallback ━━"

# llama.cpp ビルド確認 / 実行
if ! _check_llamacpp; then
  echo ""
  echo "── llama.cpp をビルドします (初回は10〜20分) ──"
  bash "$SCRIPT_DIR/setup/05_setup_llamacpp.sh" || {
    err "llama.cpp のビルドに失敗しました"
    exit 1
  }
  export PATH="$LLAMACPP_BIN:$PATH"
else
  ok "llama.cpp ビルド済み: $LLAMACPP_BIN/llama-server"
  export PATH="$LLAMACPP_BIN:$PATH"
fi

# ─── モデル選択: Instruct or JP ───────────────────────────────────────────────
echo ""
echo "── モデルを選択してください ──"
echo "  1) Instruct (英語ベース・汎用)  LiquidAI/LFM2.5-1.2B-Instruct-GGUF"
echo "  2) JP (日本語fine-tune)         LiquidAI/LFM2.5-1.2B-JP-GGUF"
echo "  3) 両方ダウンロード"
read -r -p "選択 [1/2/3] (デフォルト: 2): " model_choice
model_choice="${model_choice:-2}"

mkdir -p "$GGUF_DIR"

download_gguf() {
  local hf_repo="$1"
  local gguf_filename="$2"
  local local_path="$GGUF_DIR/$gguf_filename"

  if [ -f "$local_path" ]; then
    ok "キャッシュ済み: $local_path"
  else
    info "ダウンロード中: $hf_repo/$gguf_filename (~0.7GB)"
    if ! python3 -c "import huggingface_hub" 2>/dev/null; then
      pip3 install -q huggingface_hub
    fi
    python3 - <<PYEOF
from huggingface_hub import hf_hub_download
import sys
try:
    path = hf_hub_download(
        repo_id="$hf_repo",
        filename="$gguf_filename",
        local_dir="$GGUF_DIR",
    )
    print(f"  保存先: {path}")
except Exception as e:
    print(f"エラー: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    [ ! -f "$local_path" ] && { err "ダウンロードに失敗しました"; exit 1; }
    ok "ダウンロード完了: $local_path"
  fi
}

INSTRUCT_FILE="LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
JP_FILE="LFM2.5-1.2B-JP-Q4_K_M.gguf"
TARGET_GGUF=""

case "$model_choice" in
  1)
    download_gguf "LiquidAI/LFM2.5-1.2B-Instruct-GGUF" "$INSTRUCT_FILE"
    TARGET_GGUF="$GGUF_DIR/$INSTRUCT_FILE"
    ;;
  3)
    download_gguf "LiquidAI/LFM2.5-1.2B-Instruct-GGUF" "$INSTRUCT_FILE"
    download_gguf "LiquidAI/LFM2.5-1.2B-JP-GGUF" "$JP_FILE"
    TARGET_GGUF="$GGUF_DIR/$JP_FILE"  # JP をデフォルトサーバで起動
    ;;
  *)  # 2 (default)
    download_gguf "LiquidAI/LFM2.5-1.2B-JP-GGUF" "$JP_FILE"
    TARGET_GGUF="$GGUF_DIR/$JP_FILE"
    ;;
esac

# ─── llama-server 起動 ────────────────────────────────────────────────────────
echo ""
echo "── llama-server を起動します ──"
_start_llamacpp_server "$TARGET_GGUF" "LFM-2.5"

echo ""
echo "══════════════════════════════════════════════════════"
ok "完了: llama-server (port $LLAMACPP_SERVER_PORT) で利用可能"
echo "══════════════════════════════════════════════════════"
echo ""
echo "  API: http://localhost:$LLAMACPP_SERVER_PORT"
echo "  モデル: $TARGET_GGUF"
echo ""
echo "  テスト (OpenAI互換):"
echo "    curl -s http://localhost:$LLAMACPP_SERVER_PORT/v1/chat/completions \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"model\": \"lfm2.5\", \"messages\": [{\"role\": \"user\", \"content\": \"こんにちは\"}]}' \\"
echo "      | python3 -c \"import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])\""
echo ""
echo "  CUI チャット:"
echo "    $LLAMACPP_BIN/llama-cli -m $TARGET_GGUF -ngl 99 -c 4096 -i"
echo ""
echo "  ⚠️  注意: Jetson 再起動後は llama-server が止まります"
echo "     再起動: ./menu.sh → 3. Service → LFM-2.5 (llama-server) 起動"
echo ""
