#!/bin/bash
# lib/service.sh - サービス管理メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

menu_service() {
  while true; do
    local choice
    choice=$(ui_menu "🚀 サービス管理" \
      "1" "📊 ステータス確認 (Ollama / tegrastats)" \
      "2" "▶️  Ollama 起動" \
      "3" "⏹️  Ollama 停止" \
      "4" "🔄 Ollama 再起動" \
      "5" "📜 Ollamaログ表示" \
      "6" "📡 API 疎通テスト" \
      "7" "⚡ Jetson リソースモニタ (tegrastats)" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      1) _service_status ;;
      2) _ollama_start ;;
      3) _ollama_stop ;;
      4) _ollama_restart ;;
      5) _ollama_logs ;;
      6) _api_test ;;
      7) _tegrastats_monitor ;;
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

  ui_info "Ollama (Docker) を起動中...\nページキャッシュを解放してGPUメモリを確保します"
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
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
  ui_info "Ollamaを再起動中...\nページキャッシュを解放してGPUメモリを確保します"
  if _ollama_is_docker; then
    sudo docker stop ollama > /dev/null 2>/dev/null || true
    sleep 1
    sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
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
