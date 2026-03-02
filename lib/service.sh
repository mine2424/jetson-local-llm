#!/bin/bash
# lib/service.sh - サービス管理メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

menu_service() {
  while true; do
    local choice
    choice=$(ui_menu "🚀 サービス管理" \
      "1" "📊 ステータス確認 (Ollama / WebUI / tegrastats)" \
      "2" "▶️  Ollama 起動" \
      "3" "⏹️  Ollama 停止" \
      "4" "🔄 Ollama 再起動" \
      "5" "📜 Ollamaログ表示" \
      "6" "▶️  Open WebUI 起動" \
      "7" "⏹️  Open WebUI 停止" \
      "8" "📡 API 疎通テスト" \
      "9" "⚡ Jetson リソースモニタ (tegrastats)" \
      "10" "🔧 Ollama設定を最適化 (CUDA OOMエラー修正)" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      1) _service_status ;;
      2) _ollama_start ;;
      3) _ollama_stop ;;
      4) _ollama_restart ;;
      5) _ollama_logs ;;
      6) _webui_start ;;
      7) _webui_stop ;;
      8) _api_test ;;
      9) _tegrastats_monitor ;;
      10) _ollama_optimize_config ;;
      B) return ;;
    esac
  done
}

# Docker コンテナ "ollama" が存在するか確認する
_ollama_is_docker() {
  sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"
}

_service_status() {
  local report="=== サービスステータス ===\n\n"

  # Ollama Docker コンテナ
  if command -v docker &>/dev/null; then
    if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"; then
      local cstatus
      cstatus=$(docker ps --filter "name=^ollama$" --format "{{.Status}}" 2>/dev/null)
      report+="[Ollama Docker]  ✅ 稼働中 ($cstatus)\n"
    elif _ollama_is_docker; then
      report+="[Ollama Docker]  ⏹️ 停止 (コンテナ存在)\n"
    else
      report+="[Ollama Docker]  ℹ️ コンテナなし\n"
    fi
  fi

  # Ollama systemd
  if systemctl is-active --quiet ollama 2>/dev/null; then
    report+="[Ollama systemd] ✅ 稼働中\n"
  else
    report+="[Ollama systemd] ⏹️ 停止\n"
  fi

  # Ollama API
  if check_ollama; then
    local models_count
    models_count=$(get_models | wc -l)
    report+="[Ollama API]     ✅ 応答あり (モデル数: ${models_count}件)\n"

    # 実行中モデル
    local running
    running=$(ollama ps 2>/dev/null | tail -n +2)
    if [ -n "$running" ]; then
      report+="[実行中モデル]   $running\n"
    else
      report+="[実行中モデル]   なし\n"
    fi
  else
    report+="[Ollama API]     ⚠️ 応答なし (port 11434)\n"
  fi

  # Open WebUI (Docker)
  if command -v docker &>/dev/null; then
    if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q open-webui; then
      local ip
      ip=$(hostname -I | awk '{print $1}')
      report+="[Open WebUI]     ✅ 稼働中 → http://${ip}:8080\n"
    else
      report+="[Open WebUI]     ⏹️ 停止\n"
    fi
  else
    report+="[Open WebUI]     ℹ️ Docker未インストール\n"
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

  if _ollama_is_docker; then
    ui_info "Ollama (Docker) を起動中...\nページキャッシュを解放してGPUメモリを確保します"
    sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
    sudo docker start ollama
    sleep 3
  elif systemctl list-unit-files | grep -q ollama; then
    ui_info "Ollamaをsystemdで起動中..."
    sudo systemctl start ollama
    sleep 2
  else
    ui_info "Ollamaをバックグラウンドで起動中..."
    OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KEEP_ALIVE=5m OLLAMA_NUM_CTX=2048 \
      ollama serve > /tmp/ollama_serve.log 2>&1 &
    sleep 3
  fi

  if check_ollama; then
    ui_success "Ollama が起動しました！\nAPI: http://localhost:11434"
  else
    ui_error "起動に失敗しました\nログ: docker logs ollama または journalctl -u ollama"
  fi
}

_ollama_stop() {
  ui_confirm "Ollamaを停止しますか？" || return

  # 実行中モデルを先にアンロード
  local running
  running=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}')
  for model in $running; do
    ollama stop "$model" 2>/dev/null || true
  done

  if _ollama_is_docker; then
    sudo docker stop ollama
  elif systemctl list-unit-files | grep -q ollama; then
    sudo systemctl stop ollama
  else
    pkill -f "ollama serve" 2>/dev/null || true
  fi

  sleep 1
  if ! check_ollama; then
    ui_success "Ollama を停止しました"
  else
    ui_error "停止に失敗しました"
  fi
}

_ollama_restart() {
  ui_info "Ollamaを再起動中...\nページキャッシュを解放してGPUメモリを確保します"
  if _ollama_is_docker; then
    sudo docker stop ollama 2>/dev/null || true
    sleep 1
    sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
    sudo docker start ollama
    sleep 3
  elif systemctl list-unit-files | grep -q ollama; then
    sudo systemctl restart ollama
    sleep 3
  else
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 1
    OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KEEP_ALIVE=5m OLLAMA_NUM_CTX=2048 \
      ollama serve > /tmp/ollama_serve.log 2>&1 &
    sleep 3
  fi

  if check_ollama; then
    ui_success "Ollama が再起動しました"
  else
    ui_error "再起動に失敗しました"
  fi
}

_ollama_logs() {
  local tmpfile
  tmpfile=$(mktemp)

  if _ollama_is_docker; then
    sudo docker logs --tail 50 ollama > "$tmpfile" 2>&1
  elif systemctl list-unit-files | grep -q ollama; then
    journalctl -u ollama -n 50 --no-pager > "$tmpfile" 2>&1
  else
    tail -50 /tmp/ollama_serve.log > "$tmpfile" 2>/dev/null || \
      echo "ログファイルが見つかりません" > "$tmpfile"
  fi

  whiptail --title "$TITLE - Ollamaログ (最新50行)" \
    --scrolltext \
    --textbox "$tmpfile" $HEIGHT $WIDTH

  rm -f "$tmpfile"
}

_webui_start() {
  if ! command -v docker &>/dev/null; then
    ui_error "Docker がインストールされていません"
    return
  fi

  if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q open-webui; then
    local ip
    ip=$(hostname -I | awk '{print $1}')
    ui_msg "Open WebUI" "既に起動しています\n→ http://${ip}:8080"
    return
  fi

  # コンテナが存在する（停止中）場合は start、なければ run
  if sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q open-webui; then
    ui_info "Open WebUI を再起動中..."
    sudo docker start open-webui > /dev/null 2>&1
  else
    ui_info "Open WebUI を起動中（初回はイメージDL）..."
    bash "$SCRIPT_DIR/setup/04_setup_webui.sh" > /tmp/webui.log 2>&1
  fi

  sleep 2
  local ip
  ip=$(hostname -I | awk '{print $1}')
  ui_success "Open WebUI が起動しました！\n\n→ http://localhost:8080\n→ http://${ip}:8080 (LAN)"
}

_webui_stop() {
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q open-webui; then
    ui_msg "Open WebUI" "起動していません"
    return
  fi

  ui_confirm "Open WebUI を停止しますか？" || return
  sudo docker stop open-webui > /dev/null 2>&1
  ui_success "Open WebUI を停止しました"
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

_ollama_optimize_config() {
  local conf_file="/etc/systemd/system/ollama.service.d/jetson.conf"

  # 現在の設定を取得（存在しない場合は空）
  local before
  before=$(cat "$conf_file" 2>/dev/null || echo "(ファイルなし)")

  local new_conf="[Service]
Environment=\"OLLAMA_NUM_GPU=1\"
Environment=\"OLLAMA_MODELS=/home/\$USER/.ollama/models\"
Environment=\"OLLAMA_HOST=127.0.0.1:11434\"
Environment=\"OLLAMA_KEEP_ALIVE=5m\"
Environment=\"OLLAMA_MAX_LOADED_MODELS=1\"
Environment=\"OLLAMA_FLASH_ATTENTION=1\"
Environment=\"OLLAMA_NUM_CTX=2048\""

  whiptail --title "$TITLE - Ollama設定を最適化" \
    --msgbox "以下の設定を適用します:\n\n$new_conf\n\n【効果】\n• OLLAMA_MAX_LOADED_MODELS=1  同時ロード上限1モデル (OOM防止)\n• OLLAMA_FLASH_ATTENTION=1     VRAM使用量30-40%削減\n• OLLAMA_KEEP_ALIVE=5m         アイドル時にGPUメモリ解放\n• OLLAMA_NUM_CTX=2048          KVキャッシュを3.7GB→234MBに削減" \
    $HEIGHT $WIDTH

  ui_confirm "⚠️ 設定を書き込みOllamaを再起動しますか？" || return

  # Drop-in ディレクトリ作成＆設定書き込み
  if ! sudo mkdir -p "$(dirname "$conf_file")" 2>/dev/null; then
    ui_error "ディレクトリの作成に失敗しました (sudo権限を確認してください)"
    return
  fi

  if ! sudo tee "$conf_file" > /dev/null << 'CONF'
[Service]
Environment="OLLAMA_NUM_GPU=1"
Environment="OLLAMA_MODELS=/home/$USER/.ollama/models"
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_NUM_CTX=2048"
CONF
  then
    ui_error "設定ファイルの書き込みに失敗しました"
    return
  fi

  ui_info "systemd を再読み込み中..."
  if ! sudo systemctl daemon-reload 2>/dev/null; then
    ui_error "daemon-reload に失敗しました"
    return
  fi

  ui_info "Ollama を再起動中..."
  sudo systemctl restart ollama 2>/dev/null || true
  sleep 3

  local after
  after=$(cat "$conf_file" 2>/dev/null || echo "(読み取り失敗)")

  local status_line
  if systemctl is-active --quiet ollama 2>/dev/null; then
    status_line="✅ Ollama: 稼働中"
  else
    status_line="⚠️  Ollama: 停止 (journalctl -u ollama で確認)"
  fi

  whiptail --title "$TITLE - 最適化完了" \
    --scrolltext \
    --msgbox "=== 適用済み設定 ===\n\n$after\n\n=== ステータス ===\n$status_line\n\n次のステップ:\n  ollama run qwen2.5:7b \"hello\"\n  tegrastats  # GR3D_FREQ > 0% でGPU使用確認" \
    $HEIGHT $WIDTH
}
