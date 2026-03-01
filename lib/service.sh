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
      B) return ;;
    esac
  done
}

_service_status() {
  local report="=== サービスステータス ===\n\n"

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
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q open-webui; then
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

  if systemctl list-unit-files | grep -q ollama; then
    ui_info "Ollamaをsystemdで起動中..."
    sudo systemctl start ollama
    sleep 2
  else
    ui_info "Ollamaをバックグラウンドで起動中..."
    ollama serve > /tmp/ollama_serve.log 2>&1 &
    sleep 3
  fi

  if check_ollama; then
    ui_success "Ollama が起動しました！\nAPI: http://localhost:11434"
  else
    ui_error "起動に失敗しました\nログ: /tmp/ollama_serve.log または journalctl -u ollama"
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

  if systemctl list-unit-files | grep -q ollama; then
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
  ui_info "Ollamaを再起動中..."
  if systemctl list-unit-files | grep -q ollama; then
    sudo systemctl restart ollama
    sleep 3
  else
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 1
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

  if systemctl list-unit-files | grep -q ollama; then
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

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q open-webui; then
    local ip
    ip=$(hostname -I | awk '{print $1}')
    ui_msg "Open WebUI" "既に起動しています\n→ http://${ip}:8080"
    return
  fi

  # コンテナが存在する（停止中）場合は start、なければ run
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q open-webui; then
    ui_info "Open WebUI を再起動中..."
    docker start open-webui > /dev/null 2>&1
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
  docker stop open-webui > /dev/null 2>&1
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
