#!/bin/bash
# lib/setup.sh - セットアップ系メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

menu_setup() {
  while true; do
    local choice
    choice=$(ui_menu "⚙️  セットアップメニュー" \
      "0" "🚀 ワンショットセットアップ (install.sh)" \
      "1" "🔍 環境チェック (JetPack / CUDA / メモリ)" \
      "2" "🧩 jetson-containers セットアップ (autotag Ollama)" \
      "3" "🧠 LFM-2.5 セットアップ (SSM省メモリモデル)" \
      "4" "🌐 Open WebUI セットアップ (Docker)" \
      "5" "⚡ 電力モード設定 (7W / 15W / 25W)" \
      "6" "💾 メモリ最適化 (SSD スワップ / ZRAM 無効化 / GUI)" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      0) _setup_install ;;
      1) _setup_check ;;
      2) _setup_jetson_containers ;;
      3) _setup_lfm ;;
      4) _setup_webui ;;
      5) _setup_power ;;
      6) _setup_memory_opt ;;
      B) return ;;
    esac
  done
}

_setup_install() {
  clear
  bash "$SCRIPT_DIR/install.sh"
  press_any_key
}

_setup_check() {
  local report=""
  report+="=== Jetson 環境チェック ===\n\n"

  # JetPack
  if [ -f /etc/nv_tegra_release ]; then
    report+="[JetPack]\n$(cat /etc/nv_tegra_release)\n\n"
  else
    report+="[JetPack] ⚠️ /etc/nv_tegra_release が見つかりません\n\n"
  fi

  # CUDA
  if command -v nvcc &>/dev/null; then
    report+="[CUDA] $(nvcc --version | grep release)\n\n"
  else
    report+="[CUDA] ⚠️ nvcc が見つかりません\n\n"
  fi

  # メモリ
  report+="[メモリ]\n$(free -h)\n\n"

  # ストレージ
  report+="[ストレージ]\n$(df -h / | tail -1)\n\n"

  # 電力モード
  if command -v nvpmodel &>/dev/null; then
    report+="[電力モード]\n$(sudo nvpmodel -q 2>/dev/null)\n"
  fi

  # Ollama API
  if check_ollama; then
    report+="[Ollama API] ✅ 応答あり (http://localhost:11434)\n"
  else
    report+="[Ollama API] ⚠️ 未起動\n"
  fi

  whiptail --title "$TITLE - 環境チェック" \
    --scrolltext \
    --msgbox "$report" $HEIGHT $WIDTH
}

_setup_jetson_containers() {
  clear
  bash "$SCRIPT_DIR/setup/08_setup_jetson_containers.sh"
  press_any_key
}

_setup_memory_opt() {
  clear
  bash "$SCRIPT_DIR/setup/07_setup_memory_opt.sh"
  press_any_key
}

_setup_webui() {
  if ! command -v docker &>/dev/null; then
    ui_error "Dockerが見つかりません。\n\n以下を実行してDockerをインストールしてください:\n  curl -fsSL https://get.docker.com | sh\n  sudo usermod -aG docker \$USER"
    return
  fi

  if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q open-webui; then
    local ip
    ip=$(hostname -I | awk '{print $1}')
    ui_msg "Open WebUI" "既に起動しています！\n\n→ http://localhost:8080\n→ http://${ip}:8080 (LAN)"
    return
  fi

  ui_confirm "Open WebUI (Docker) を起動しますか？\n(初回はイメージのダウンロードがあります)" || return
  ui_info "Open WebUI を起動中..."
  if bash "$SCRIPT_DIR/setup/04_setup_webui.sh" > /tmp/webui.log 2>&1; then
    local ip
    ip=$(hostname -I | awk '{print $1}')
    ui_success "Open WebUI 起動完了！\n\nブラウザで開く:\n→ http://localhost:8080\n→ http://${ip}:8080 (LAN内)"
  else
    ui_error "起動に失敗しました。\nログ: /tmp/webui.log"
  fi
}

_setup_lfm() {
  if ! check_ollama; then
    ui_error "Ollama API が応答しません\nまず Ollama を起動してください\n(Service → Ollama 起動)"
    return
  fi
  clear
  bash "$SCRIPT_DIR/setup/06_setup_lfm.sh"
  press_any_key
}

_setup_power() {
  local choice
  choice=$(ui_menu "⚡ 電力モード選択" \
    "0" "MAXN     - 25W (最高性能・推論向け)" \
    "1" "MODE_15W - 15W (バランス)" \
    "2" "MODE_7W  - 7W  (省電力)" \
  ) || return

  if ui_confirm "電力モード $choice に切り替えます。よろしいですか？"; then
    sudo nvpmodel -m "$choice" && sudo jetson_clocks
    ui_success "電力モードを切り替えました。\n\n$(sudo nvpmodel -q 2>/dev/null)"
  fi
}
