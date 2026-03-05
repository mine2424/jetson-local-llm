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

# ─── 起動時 GPU / ファン 最適化を暗黙適用 ───────────────────────────────────────
# menu.sh を起動するだけで以下が自動適用される:
#   - MAXN 電源モード (nvpmodel)
#   - GPU / CPU クロック固定 (jetson_clocks)
#   - ファン積極冷却 (nvfancontrol 停止 → PWM 手動設定)
_perf_init() {
  # 電源モード MAXN
  local maxn_id
  maxn_id=$(grep -i "POWER_MODEL" /etc/nvpmodel.conf 2>/dev/null \
    | grep -i "MAXN" | grep -o "ID=[0-9]*" | head -1 | cut -d= -f2 || echo "0")
  sudo nvpmodel -m "${maxn_id:-0}" 2>/dev/null || true

  # クロック固定
  sudo jetson_clocks 2>/dev/null || true

  # ファン: nvfancontrol (quiet) を止めて PWM を積極冷却に設定
  local fan_pwm
  fan_pwm=$(ls /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1 2>/dev/null | head -1)
  [ -z "$fan_pwm" ] && fan_pwm=$(ls /sys/class/hwmon/hwmon*/pwm1 2>/dev/null | head -1)
  if [ -n "$fan_pwm" ]; then
    sudo systemctl stop nvfancontrol 2>/dev/null || true
    sudo sh -c "echo 1 > ${fan_pwm}_enable" 2>/dev/null || true
    sudo sh -c "echo 200 > $fan_pwm" 2>/dev/null || true  # 78% — 積極冷却
  fi
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
