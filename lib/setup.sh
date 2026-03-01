#!/bin/bash
# lib/setup.sh - セットアップ系メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

menu_setup() {
  while true; do
    local choice
    choice=$(ui_menu "⚙️  セットアップメニュー" \
      "1" "🔍 環境チェック (JetPack / CUDA / メモリ)" \
      "2" "📦 Ollama インストール / 更新" \
      "3" "🔨 llama.cpp ビルド (CUDA対応)" \
      "4" "🌐 Open WebUI セットアップ (Docker)" \
      "5" "⚡ 電力モード設定 (7W / 15W / 25W)" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      1) _setup_check ;;
      2) _setup_ollama ;;
      3) _setup_llamacpp ;;
      4) _setup_webui ;;
      5) _setup_power ;;
      B) return ;;
    esac
  done
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

  # Ollama
  if command -v ollama &>/dev/null; then
    report+="[Ollama] $(ollama --version)\n"
  else
    report+="[Ollama] ⚠️ 未インストール\n"
  fi

  whiptail --title "$TITLE - 環境チェック" \
    --scrolltext \
    --msgbox "$report" $HEIGHT $WIDTH
}

_setup_ollama() {
  if command -v ollama &>/dev/null; then
    local ver
    ver=$(ollama --version)
    if ! ui_confirm "Ollamaは既にインストールされています ($ver)\n\n更新しますか？"; then
      return
    fi
  fi

  ui_info "Ollamaをインストール中...\n(完了後、自動でメニューに戻ります)"
  if bash "$SCRIPT_DIR/setup/01_install_ollama.sh" > /tmp/ollama_install.log 2>&1; then
    ui_success "Ollama インストール完了！\n\n$(ollama --version)"
  else
    ui_error "インストールに失敗しました。\nログ: /tmp/ollama_install.log"
  fi
}

_setup_llamacpp() {
  ui_confirm "llama.cpp を CUDA対応でビルドします。\n10〜20分かかります。続けますか？" || return
  ui_info "llama.cpp をビルド中...\nこのウィンドウはしばらく動きません"
  if bash "$SCRIPT_DIR/setup/02_install_llamacpp.sh" > /tmp/llamacpp_build.log 2>&1; then
    ui_success "llama.cpp ビルド完了！\n\nバイナリ: ~/llama.cpp/build/bin/llama-cli"
  else
    ui_error "ビルドに失敗しました。\nログ: /tmp/llamacpp_build.log"
  fi
}

_setup_webui() {
  if ! command -v docker &>/dev/null; then
    ui_error "Dockerが見つかりません。\n\n以下を実行してDockerをインストールしてください:\n  curl -fsSL https://get.docker.com | sh\n  sudo usermod -aG docker \$USER"
    return
  fi

  if docker ps | grep -q open-webui; then
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
