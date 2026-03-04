#!/bin/bash
# ============================================================
#  Jetson Local LLM - メインメニュー
#  使い方: ./menu.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ライブラリ読み込み
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/setup.sh"
source "$SCRIPT_DIR/lib/models.sh"
source "$SCRIPT_DIR/lib/service.sh"
source "$SCRIPT_DIR/lib/bench.sh"

# whiptail チェック
check_whiptail

# ----- メインループ -----
main_menu() {
  while true; do
    # ステータスバー（上部に表示する情報）
    local ollama_status="⏹️ 停止"
    local model_count="0"
    if check_ollama; then
      ollama_status="✅ 稼働中"
      model_count=$(get_models | grep -c . 2>/dev/null || echo "0")
    fi

    local cuda_status="❌ CPU only"
    if ls "$HOME/llama.cpp/build/bin/libggml-cuda.so"* >/dev/null 2>&1; then
      cuda_status="✅ CUDA"
    fi

    local mem_used mem_total
    mem_used=$(free -h | awk '/^Mem/{print $3}')
    mem_total=$(free -h | awk '/^Mem/{print $2}')

    local status_line="Ollama: $ollama_status  |  llama.cpp: $cuda_status  |  モデル: ${model_count}件  |  RAM: $mem_used / $mem_total"

    local choice
    choice=$(whiptail \
      --title "🤖 Jetson Local LLM" \
      --menu "$status_line\n\nメニューを選択:" \
      $HEIGHT $WIDTH 9 \
      "1" "⚙️  Setup        - jetson-containers セットアップ・モデル導入" \
      "2" "📦 Models       - モデル管理 (pull / import / delete)" \
      "3" "🚀 Service      - サービス管理 (Ollama 起動・停止・ログ)" \
      "4" "⚡ Benchmark    - 性能計測" \
      "Q" "🚪 終了" \
      3>&1 1>&2 2>&3) || break

    case "$choice" in
      1) menu_setup ;;
      2) menu_models ;;
      3) menu_service ;;
      4) menu_bench ;;
      Q) break ;;
    esac
  done

  clear
  echo "👋 Jetson Local LLM を終了しました"
}

# ----- エントリーポイント -----
# 引数があれば直接サブメニューへ
case "${1:-}" in
  setup)    menu_setup ;;
  models)   menu_models ;;
  service)  menu_service ;;
  bench)    menu_bench ;;
  *)        main_menu ;;
esac
