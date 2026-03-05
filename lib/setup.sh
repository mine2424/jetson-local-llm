#!/bin/bash
# lib/setup.sh - セットアップ系メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

menu_setup() {
  while true; do
    local choice
    choice=$(ui_menu "⚙️  セットアップ" \
      "1" "🚀 初回セットアップ    — jetson-containers + モデル pull" \
      "2" "🔧 GPU・ファン 診断・修正 — GPU env修正・冷却設定" \
      "3" "🔨 llama.cpp ビルド    — CUDA sm_87 対応ビルド" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      1) _setup_full ;;
      2) _setup_fix_gpu_fan ;;
      3) _setup_llamacpp ;;
      B) return ;;
    esac
  done
}

# ─── 1. 初回セットアップ ─────────────────────────────────────────────────────
_setup_full() {
  # Step 1: jetson-containers + Ollama コンテナ
  clear
  bash "$SCRIPT_DIR/setup/08_setup_jetson_containers.sh"
  press_any_key

  if ! check_ollama; then
    ui_error "Ollama API が応答しません\njetson-containers のセットアップを確認してください"
    return
  fi

  # Step 2: モデル選択 & pull
  local items=(
    "qwen3.5:4b-q4_K_M"                             "★万能  Qwen3.5 4B    vision+tools+thinking  3.4GB" "ON"
    "qwen2.5:7b-instruct-q4_K_M"                    "★日本語 Qwen2.5 7B   日本語最高品質          4.7GB" "OFF"
    "qwen2.5:3b-instruct-q4_K_M"                    " 日本語 Qwen2.5 3B   日本語軽量              1.9GB" "OFF"
    "deepseek-r1:1.5b-qwen-distill-q5_K_M"          " 推論  DeepSeek-R1 1.5B  CoT推論・軽量       1.2GB" "OFF"
    "deepseek-r1:7b-qwen-distill-q4_K_M"            " 推論  DeepSeek-R1 7B   CoT推論・高性能      4.7GB" "OFF"
    "qwen2.5-coder:7b-instruct-q4_K_M"              " コード Qwen2.5-Coder 7B コード最高性能      4.7GB" "OFF"
    "qwen2.5-coder:3b-instruct-q4_K_M"              " コード Qwen2.5-Coder 3B コード軽量          1.9GB" "OFF"
    "gemma3:4b-it-q4_K_M"                           " 汎用  Gemma3 4B    バランス優秀             2.6GB" "OFF"
    "gemma2:2b-instruct-q5_K_M"                     " 汎用  Gemma2 2B    軽量・優秀               1.6GB" "OFF"
    "phi3.5:3.8b-mini-instruct-q4_K_M"              " 推論  Phi3.5 3.8B  論理推論・MS製           2.2GB" "OFF"
    "phi4-mini:3.8b-instruct-q4_K_M"                " 推論  Phi4-mini    Phi最新世代              2.4GB" "OFF"
    "smollm2:1.7b-instruct-q5_K_M"                  " 超軽量 SmolLM2 1.7B 爆速・小さいが賢い      1.0GB" "OFF"
    "smollm2:360m-instruct-q8_0"                    " 超軽量 SmolLM2 0.36B 最軽量                 0.4GB" "OFF"
    "moondream2"                                     " ビジョン moondream2  画像理解・超軽量        1.7GB" "OFF"
    "llava:7b-v1.6-mistral-q4_K_M"                  " ビジョン LLaVA 7B   画像+テキスト           4.5GB" "OFF"
    "starcoder2:3b-q4_K_M"                          " コード StarCoder2 3B コード補完              1.9GB" "OFF"
    "granite3.1-moe:3b-instruct-q4_K_M"             " 多言語 Granite3.1 MoE IBM製・効率的         2.1GB" "OFF"
    "llama3.2:3b-instruct-q4_K_M"                   " 汎用  Llama3.2 3B  英語汎用                 2.0GB" "OFF"
    "mistral:7b-instruct-v0.3-q4_K_M"               " 汎用  Mistral 7B   安定・汎用               4.1GB" "OFF"
    "LFM-2.5"                                        " SSM   LFM-2.5      125K ctx・省メモリ       731MB" "OFF"
  )

  local selected
  selected=$(ui_checklist "ダウンロードするモデルを選択" "${items[@]}") || return
  [ -z "$selected" ] && return

  local failed=()
  for model in $selected; do
    model=$(echo "$model" | tr -d '"')
    if [ "$model" = "LFM-2.5" ]; then
      clear
      bash "$SCRIPT_DIR/setup/06_setup_lfm.sh"
      press_any_key
      continue
    fi
    ui_info "pull 中: $model"
    local status
    status=$(curl -s -X POST http://localhost:11434/api/pull \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$model\"}" 2>/dev/null | \
      python3 -c "
import sys, json
last = ''
for l in sys.stdin:
    try: last = json.loads(l.strip()).get('status', last)
    except: pass
print(last)" 2>/dev/null || echo "error")
    [ "$status" != "success" ] && failed+=("$model")
  done

  if [ ${#failed[@]} -eq 0 ]; then
    ui_success "セットアップ完了！\n\n次のステップ: Service → 起動 → チャット"
  else
    ui_error "以下のモデルのダウンロードに失敗:\n${failed[*]}"
  fi
}

# ─── 2. GPU・ファン 診断・修正 ──────────────────────────────────────────────────
_setup_fix_gpu_fan() {
  # GPU 修正
  clear
  echo "═══════════════════════════════════════════"
  echo "  [1/2] GPU 環境変数 修正・確認"
  echo "═══════════════════════════════════════════"
  bash "$SCRIPT_DIR/scripts/fix_ollama_gpu.sh" --force
  press_any_key

  # ファン冷却設定
  clear
  echo "═══════════════════════════════════════════"
  echo "  [2/2] ファン積極冷却 設定"
  echo "═══════════════════════════════════════════"
  bash "$SCRIPT_DIR/setup/10_setup_fan.sh"
  press_any_key
}

# ─── 3. llama.cpp ビルド ─────────────────────────────────────────────────────
_setup_llamacpp() {
  if [ -f "$HOME/llama.cpp/build/bin/llama-server" ]; then
    ui_confirm "llama.cpp は既にビルド済みです。再ビルドしますか？" || return
  else
    ui_confirm "llama.cpp を CUDA 対応でビルドします（初回 10〜20 分）。続けますか？" || return
  fi
  clear
  export PATH="/usr/local/cuda/bin:$PATH"
  bash "$SCRIPT_DIR/setup/05_setup_llamacpp.sh"
  press_any_key
}
