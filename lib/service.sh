#!/bin/bash
# lib/service.sh - サービス管理メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

LLAMACPP_SERVER_PORT=8081
LLAMACPP_BIN="$HOME/llama.cpp/build/bin"
GGUF_DIR="$HOME/.ollama/models/lfm25_gguf"

menu_service() {
  while true; do
    # llama-server 状態をヘッダに反映
    local lls_status="⏹️ 停止"
    if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
      lls_status="✅ 稼働中"
    fi

    local choice
    choice=$(ui_menu "🚀 サービス管理  [LFM-2.5 llama-server: $lls_status]" \
      "1"  "📊 ステータス確認 (全サービス)" \
      "2"  "▶️  Ollama 起動 (drop_caches → docker start)" \
      "3"  "⏹️  Ollama 停止" \
      "4"  "🔄 Ollama 再起動" \
      "5"  "📜 Ollamaログ表示" \
      "6"  "💬 ollama run (インタラクティブチャット)" \
      "7"  "📡 API 疎通テスト (Ollama)" \
      "8"  "🐳 コンテナイメージ更新 (autotag → 再作成)" \
      "9"  "⚡ Jetson リソースモニタ (tegrastats)" \
      "L1" "▶️  LFM-2.5 llama-server 起動 (port $LLAMACPP_SERVER_PORT)" \
      "L2" "⏹️  LFM-2.5 llama-server 停止" \
      "L3" "📡 LFM-2.5 API 疎通テスト" \
      "L4" "📜 llama-server ログ表示" \
      "B"  "← 戻る"
    ) || return

    case "$choice" in
      1)  _service_status ;;
      2)  _ollama_start ;;
      3)  _ollama_stop ;;
      4)  _ollama_restart ;;
      5)  _ollama_logs ;;
      6)  _ollama_run_interactive ;;
      7)  _api_test ;;
      8)  _container_update ;;
      9)  _tegrastats_monitor ;;
      L1) _llamacpp_server_start ;;
      L2) _llamacpp_server_stop ;;
      L3) _llamacpp_api_test ;;
      L4) _llamacpp_logs ;;
      B)  return ;;
    esac
  done
}

# Docker コンテナ "ollama" が存在するか確認する
_ollama_is_docker() {
  sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"
}

# GPU/CPU 最適化を暗黙適用 (全起動関数から呼ぶ)
# - MAXN 電源モード (nvpmodel -m 0)
# - クロック固定   (jetson_clocks)
# - ページキャッシュ解放 (drop_caches)
_apply_perf_mode() {
  sudo nvpmodel -m 0     2>/dev/null || true
  sudo jetson_clocks     2>/dev/null || true
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
}

_service_status() {
  local report="=== サービスステータス ===\n\n"

  # Ollama Docker コンテナ
  if command -v docker &>/dev/null; then
    if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"; then
      local cstatus cimage
      cstatus=$(sudo docker ps --filter "name=^ollama$" --format "{{.Status}}" 2>/dev/null)
      cimage=$(sudo docker ps --filter "name=^ollama$" --format "{{.Image}}" 2>/dev/null)
      report+="[Ollama Docker]  ✅ 稼働中 ($cstatus)\n"
      report+="[イメージ]       $cimage\n"
    elif _ollama_is_docker; then
      report+="[Ollama Docker]  ⏹️ 停止 (コンテナ存在)\n"
    else
      report+="[Ollama Docker]  ℹ️ コンテナなし\n"
    fi
  fi

  # LFM-2.5 llama-server
  if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    local pid
    pid=$(cat /tmp/llama-server.pid 2>/dev/null || echo "?")
    local model_file
    model_file=$(ls "$GGUF_DIR"/*.gguf 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "不明")
    report+="[LFM-2.5 Server] ✅ 稼働中 (port $LLAMACPP_SERVER_PORT, PID: $pid)\n"
    report+="[モデル]         $model_file\n"
  else
    if [ -f "$LLAMACPP_BIN/llama-server" ]; then
      report+="[LFM-2.5 Server] ⏹️ 停止 (llama.cpp ビルド済み)\n"
    else
      report+="[LFM-2.5 Server] ℹ️ 未セットアップ (Setup → LFM-2.5)\n"
    fi
  fi

  # Ollama API
  if check_ollama; then
    local models_count
    models_count=$(get_models | wc -l)
    report+="[Ollama API]     ✅ 応答あり (モデル数: ${models_count}件)\n"

    # 実行中モデル (API /api/ps)
    local running
    running=$(curl -s http://localhost:11434/api/ps 2>/dev/null | \
      python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for m in data.get('models', []):
        size_mb = m.get('size_vram', 0) // 1048576
        print(f\"  {m['name']}  ({size_mb}MB VRAM)\")
except:
    pass
" 2>/dev/null || true)
    if [ -n "$running" ]; then
      report+="[実行中モデル]   \n$running\n"
    else
      report+="[実行中モデル]   なし\n"
    fi
  else
    report+="[Ollama API]     ⚠️ 応答なし (port 11434)\n"
  fi

  # メモリ
  report+="\n=== メモリ ===\n$(free -h | head -2)\n"

  # CPU / GPU 温度
  if command -v tegrastats &>/dev/null; then
    local tstat
    tstat=$(timeout 2 tegrastats 2>/dev/null | head -1 || echo "取得失敗")
    report+="\n=== Tegrastats ===\n$tstat\n"
  fi

  whiptail --title "$TITLE - ステータス" \
    --scrolltext \
    --msgbox "$report" $HEIGHT $WIDTH
}

_ollama_start() {
  if check_ollama; then
    ui_msg "Ollama" "Ollamaは既に起動しています"
    return
  fi

  if ! _ollama_is_docker; then
    ui_error "Ollama コンテナが見つかりません\n\nまず Setup → jetson-containers セットアップを実行してください"
    return
  fi

  ui_info "Ollama (Docker) を起動中...\nMAXN 電源モード + クロック固定 + メモリ解放を適用します"
  _apply_perf_mode
  sudo docker start ollama > /dev/null 2>&1

  local i=0
  while [ $i -lt 10 ]; do
    if check_ollama; then
      ui_success "Ollama が起動しました！\nAPI: http://localhost:11434"
      return
    fi
    sleep 3
    i=$((i + 1))
  done
  ui_error "起動に失敗しました\nログ: sudo docker logs ollama"
}

_ollama_stop() {
  ui_confirm "Ollamaを停止しますか？" || return

  # ロード中モデルを API 経由でアンロード (keep_alive=0)
  local running
  running=$(curl -s http://localhost:11434/api/ps 2>/dev/null | \
    python3 -c "
import sys, json
try:
    for m in json.load(sys.stdin).get('models', []):
        print(m['name'])
except:
    pass
" 2>/dev/null || true)
  for model in $running; do
    curl -s -X POST http://localhost:11434/api/generate \
      -d "{\"model\": \"$model\", \"keep_alive\": 0}" > /dev/null 2>&1 || true
  done

  if _ollama_is_docker; then
    sudo docker stop ollama > /dev/null 2>&1
  fi

  sleep 1
  if ! check_ollama; then
    ui_success "Ollama を停止しました"
  else
    ui_error "停止に失敗しました"
  fi
}

_ollama_restart() {
  ui_info "Ollamaを再起動中...\nMAXN 電源モード + クロック固定 + メモリ解放を適用します"
  if _ollama_is_docker; then
    sudo docker stop ollama > /dev/null 2>/dev/null || true
    sleep 1
    _apply_perf_mode
    sudo docker start ollama > /dev/null 2>&1
    sleep 3
  else
    ui_error "Ollama コンテナが見つかりません\nSetup → jetson-containers セットアップを実行してください"
    return
  fi

  if check_ollama; then
    ui_success "Ollama が再起動しました"
  else
    ui_error "再起動に失敗しました\nログ: sudo docker logs ollama"
  fi
}

_ollama_logs() {
  local tmpfile
  tmpfile=$(mktemp)

  if _ollama_is_docker; then
    sudo docker logs --tail 50 ollama > "$tmpfile" 2>&1
  else
    echo "Ollama コンテナが見つかりません" > "$tmpfile"
  fi

  whiptail --title "$TITLE - Ollamaログ (最新50行)" \
    --scrolltext \
    --textbox "$tmpfile" $HEIGHT $WIDTH

  rm -f "$tmpfile"
}

_ollama_run_interactive() {
  if ! check_ollama; then
    ui_error "Ollama API が応答しません\nまず Ollama を起動してください (項目 2)"
    return
  fi

  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_error "モデルがインストールされていません\nModels メニューから pull してください"
    return
  fi

  local items=()
  while IFS= read -r m; do
    items+=("$m" "")
  done <<< "$models"

  local target
  target=$(ui_menu "💬 チャットするモデルを選択" "${items[@]}") || return

  clear
  bash "$SCRIPT_DIR/ollama-run.sh" "$target"
  press_any_key
}

_container_update() {
  if ! command -v autotag &>/dev/null; then
    ui_error "autotag が見つかりません\nSetup → jetson-containers セットアップを先に実行してください"
    return
  fi

  local new_image
  new_image=$(autotag ollama 2>/dev/null || true)
  if [ -z "$new_image" ]; then
    ui_error "autotag でイメージを解決できませんでした\nJetPack バージョンを確認してください"
    return
  fi

  local current_image=""
  if _ollama_is_docker; then
    current_image=$(sudo docker inspect ollama --format '{{.Config.Image}}' 2>/dev/null || true)
  fi

  ui_confirm "コンテナイメージを更新します\n\n現在: ${current_image:-不明}\n新規: $new_image\n\n既存コンテナを停止・削除して再作成します。よろしいですか？" || return

  clear
  echo "── [1/4] イメージをダウンロード中: $new_image ──"
  sudo docker pull "$new_image"

  echo ""
  echo "── [2/4] 既存コンテナを停止・削除 ──"
  sudo docker stop ollama 2>/dev/null || true
  _apply_perf_mode
  sudo docker rm ollama 2>/dev/null || true

  echo ""
  echo "── [3/4] 新しいコンテナを起動 ──"
  mkdir -p "$HOME/.ollama/models"
  sudo docker run -d \
    --name ollama \
    --runtime nvidia \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e OLLAMA_FLASH_ATTENTION=1 \
    -e OLLAMA_MAX_LOADED_MODELS=1 \
    -e OLLAMA_KEEP_ALIVE=5m \
    -e OLLAMA_NUM_CTX=2048 \
    -e OLLAMA_HOST=0.0.0.0:11434 \
    -v "$HOME/.ollama/models:/data/models/ollama/models" \
    -p 127.0.0.1:11434:11434 \
    --restart unless-stopped \
    "$new_image" \
    /bin/sh -c '/start_ollama; tail -f /data/logs/ollama.log'

  echo ""
  echo "── [4/4] API 応答待ち ──"
  local i=0
  while [ $i -lt 10 ]; do
    if check_ollama; then
      ui_success "コンテナイメージの更新が完了しました\n\nイメージ: $new_image\nAPI: http://localhost:11434"
      return
    fi
    sleep 3
    i=$((i + 1))
  done
  ui_error "API が応答しません\nログ: sudo docker logs ollama"
}

_api_test() {
  if ! check_ollama; then
    ui_error "OllamaのAPIが応答しません\nまずOllamaを起動してください"
    return
  fi

  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_error "モデルがインストールされていません"
    return
  fi

  local items=()
  while IFS= read -r m; do
    items+=("$m" "")
  done <<< "$models"

  local target
  target=$(ui_menu "テストに使うモデルを選択" "${items[@]}") || return

  ui_info "API テスト中...\n\ncurl http://localhost:11434/v1/chat/completions"

  local response
  response=$(curl -s http://localhost:11434/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$target\", \"messages\": [{\"role\": \"user\", \"content\": \"Hi! Reply in one sentence.\"}]}" \
    2>&1)

  local content
  content=$(echo "$response" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null \
    || echo "レスポンスのパースに失敗\n\nRAW:\n$response")

  whiptail --title "$TITLE - API テスト結果 ($target)" \
    --msgbox "✅ OpenAI互換APIが正常に応答しました\n\n応答:\n$content" \
    $HEIGHT $WIDTH
}

_tegrastats_monitor() {
  if ! command -v tegrastats &>/dev/null; then
    ui_error "tegrastats が見つかりません\nJetPackが正しくインストールされているか確認してください"
    return
  fi

  ui_msg "tegrastats モニタ" "Ctrl+C で終了します\n\nターミナルで tegrastats を起動します..."
  echo "--- tegrastats (Ctrl+C で停止) ---"
  tegrastats --interval 1000
  press_any_key
}

# ═══════════════════════════════════════════════════════════
# LFM-2.5 llama-server 管理
# ═══════════════════════════════════════════════════════════

_llamacpp_server_start() {
  if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    ui_msg "llama-server" "既に port $LLAMACPP_SERVER_PORT で稼働しています"
    return
  fi

  if [ ! -f "$LLAMACPP_BIN/llama-server" ]; then
    ui_error "llama.cpp がビルドされていません\n\nSetup → LFM-2.5 セットアップ を実行してください"
    return
  fi

  # GGUFファイルを選択
  local gguf_files
  gguf_files=$(ls "$GGUF_DIR"/*.gguf 2>/dev/null)
  if [ -z "$gguf_files" ]; then
    ui_error "GGUFファイルが見つかりません: $GGUF_DIR\n\nSetup → LFM-2.5 セットアップ を実行してください"
    return
  fi

  local items=()
  while IFS= read -r f; do
    items+=("$f" "$(basename "$f")")
  done <<< "$gguf_files"

  local target
  target=$(ui_menu "起動するモデル (GGUF) を選択" "${items[@]}") || return

  ui_info "llama-server を起動中...\nMAXN + jetson_clocks + GPU全オフロード(-ngl 999) + Flash Attention\nport: $LLAMACPP_SERVER_PORT"

  # 既存プロセスを停止
  pkill -f "llama-server.*$LLAMACPP_SERVER_PORT" 2>/dev/null || true
  sleep 1

  # パフォーマンス最適化を暗黙適用
  _apply_perf_mode

  # CUDA最適化環境変数
  # FORCE_MMQ: Q4_K_M等の量子化モデルでCUDA行列乗算を強制 (+10~30% speed)
  export GGML_CUDA_FORCE_MMQ=1
  export GGML_CUDA_NO_PEER_COPY=1
  export CUDA_VISIBLE_DEVICES=0

  nohup "$LLAMACPP_BIN/llama-server" \
    -m "$target" \
    -ngl 999 \
    --flash-attn \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    -c 4096 \
    -b 512 -ub 512 \
    -t 6 \
    --host 0.0.0.0 \
    --port "$LLAMACPP_SERVER_PORT" \
    --log-disable \
    > /tmp/llama-server.log 2>&1 &
  echo $! > /tmp/llama-server.pid

  # 起動待機
  local i=0
  while [ $i -lt 20 ]; do
    if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
      ui_success "llama-server 起動完了！\n\nAPI: http://localhost:$LLAMACPP_SERVER_PORT\nモデル: $(basename "$target")\n\nOpenAI互換エンドポイント:\n  http://localhost:$LLAMACPP_SERVER_PORT/v1/chat/completions"
      return
    fi
    sleep 1
    i=$((i + 1))
  done
  ui_error "起動に失敗しました\nログ: /tmp/llama-server.log"
}

_llamacpp_server_stop() {
  if ! curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    ui_msg "llama-server" "稼働していません"
    return
  fi

  ui_confirm "llama-server を停止しますか？" || return

  local pid
  pid=$(cat /tmp/llama-server.pid 2>/dev/null)
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
  fi
  pkill -f "llama-server.*$LLAMACPP_SERVER_PORT" 2>/dev/null || true

  sleep 1
  if ! curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    ui_success "llama-server を停止しました"
  else
    ui_error "停止に失敗しました"
  fi
}

_llamacpp_api_test() {
  if ! curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    ui_error "llama-server が起動していません\n(L1) LFM-2.5 llama-server 起動 を実行してください"
    return
  fi

  local prompt
  prompt=$(ui_input "テストプロンプト" "日本語で自己紹介してください。") || return
  [ -z "$prompt" ] && return

  ui_info "LFM-2.5 で推論中...\n(10〜30秒かかります)"

  local result
  result=$(curl -s "http://localhost:$LLAMACPP_SERVER_PORT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json; print(json.dumps({
      'model': 'lfm2.5',
      'messages': [{'role': 'user', 'content': '$prompt'}]
    }))")" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'])
except Exception as e:
    print(f'パースエラー: {e}')
" 2>&1)

  whiptail --title "$TITLE - LFM-2.5 応答 (port $LLAMACPP_SERVER_PORT)" \
    --scrolltext \
    --msgbox "$result" $HEIGHT $WIDTH
}

_llamacpp_logs() {
  local logfile="/tmp/llama-server.log"
  if [ ! -f "$logfile" ]; then
    ui_msg "llama-server ログ" "ログファイルが見つかりません: $logfile\nまず llama-server を起動してください"
    return
  fi

  local tmpfile
  tmpfile=$(mktemp)
  tail -50 "$logfile" > "$tmpfile"
  whiptail --title "$TITLE - llama-server ログ (最新50行)" \
    --scrolltext \
    --textbox "$tmpfile" $HEIGHT $WIDTH
  rm -f "$tmpfile"
}
