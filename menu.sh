#!/bin/bash
# ============================================================
#  Jetson Local LLM - メインメニュー
#  使い方: ./menu.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/setup.sh"
source "$SCRIPT_DIR/lib/models.sh"
source "$SCRIPT_DIR/lib/service.sh"
source "$SCRIPT_DIR/lib/bench.sh"

check_whiptail

# ─── 起動時 GPU 最適化を暗黙適用 ──────────────────────────────────────────────
# menu.sh を起動するだけで MAXN 電源モード + クロック固定が有効になる
_perf_init() {
  local maxn_id
  maxn_id=$(grep -i "POWER_MODEL" /etc/nvpmodel.conf 2>/dev/null \
    | grep -i "MAXN" | grep -o "ID=[0-9]*" | head -1 | cut -d= -f2 || echo "0")
  sudo nvpmodel -m "${maxn_id:-0}" 2>/dev/null || true
  sudo jetson_clocks 2>/dev/null || true
}
_perf_init

# ─── メインループ ──────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    # ステータスバー
    local ollama_st="⏹️ 停止"
    local model_count="0"
    if check_ollama 2>/dev/null; then
      ollama_st="✅ 稼働"
      model_count=$(get_models 2>/dev/null | grep -c . || echo "0")
    fi

    local cuda_st="❌ CPU"
    ls "$HOME/llama.cpp/build/bin/libggml-cuda.so"* >/dev/null 2>&1 && cuda_st="✅ CUDA"

    local mem
    mem=$(free -h 2>/dev/null | awk '/^Mem/{print $3"/"$2}' || echo "?")

    local header="Ollama: $ollama_st  |  CUDA: $cuda_st  |  モデル: ${model_count}件  |  RAM: $mem"

    local choice
    choice=$(whiptail \
      --title "🤖 Jetson Local LLM" \
      --menu "$header\n\n操作を選択:" \
      $HEIGHT $WIDTH 6 \
      "1" "🚀 Service   — 起動・停止・チャット・ログ" \
      "2" "📦 Models    — モデル管理 (pull / 削除)" \
      "3" "⚙️  Setup     — 初回セットアップ・GPU修正" \
      "4" "📊 Benchmark — 性能計測" \
      "Q" "🚪 終了" \
      3>&1 1>&2 2>&3) || break

    case "$choice" in
      1) menu_service ;;
      2) menu_models ;;
      3) menu_setup ;;
      4) menu_bench ;;
      Q) break ;;
    esac
  done

  clear
  echo "👋 終了しました"
}

case "${1:-}" in
  service)   menu_service ;;
  models)    menu_models ;;
  setup)     menu_setup ;;
  bench)     menu_bench ;;
  *)         main_menu ;;
esac
