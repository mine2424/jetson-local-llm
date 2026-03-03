#!/bin/bash
# lib/setup.sh - セットアップ系メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

menu_setup() {
  while true; do
    local choice
    choice=$(ui_menu "⚙️  セットアップメニュー" \
      "1" "🧩 jetson-containers セットアップ (autotag Ollama)" \
      "2" "📦 jetson-containers + モデルpull (まとめてセットアップ)" \
      "3" "🧠 LFM-2.5 セットアップ (SSM省メモリモデル・GGUF)" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      1) _setup_jetson_containers ;;
      2) _setup_jc_with_model ;;
      3) _setup_lfm ;;
      B) return ;;
    esac
  done
}

_setup_jetson_containers() {
  clear
  bash "$SCRIPT_DIR/setup/08_setup_jetson_containers.sh"
  press_any_key
}

_setup_jc_with_model() {
  # Step 1: jetson-containers セットアップ
  clear
  bash "$SCRIPT_DIR/setup/08_setup_jetson_containers.sh"
  local rc=$?
  press_any_key
  [ $rc -ne 0 ] && return

  # Ollama API が応答しているか確認
  if ! check_ollama; then
    ui_error "Ollama API が応答しません\njetson-containers のセットアップを確認してください"
    return
  fi

  # Step 2: モデル選択 & pull
  # 3B以上は Q4_K_M 量子化必須。LFM-2.5 はバイナリアップグレード後に API pull。
  local items=(
    "qwen2.5:3b-instruct-q4_K_M"              "[JA]  Qwen2.5 3B Q4        | 軽量日本語 ★         | 1.9GB" "ON"
    "qwen2.5:7b-instruct-q4_K_M"              "[JA]  Qwen2.5 7B Q4        | 日本語最高性能       | 4.7GB" "OFF"
    "qwen2.5-coder:3b-instruct-q4_K_M"        "[CODE] Qwen2.5-Coder 3B Q4 | コード生成軽量       | 1.9GB" "OFF"
    "qwen3.5:0.8b"                             "[Q3.5] Qwen3.5 0.8B        | vision+tools・超軽量  | 1.0GB" "OFF"
    "qwen3.5:2b-q4_K_M"                       "[Q3.5] Qwen3.5 2B Q4       | vision+tools・軽量    | 1.9GB" "OFF"
    "qwen3.5:4b-q4_K_M"                       "[Q3.5] Qwen3.5 4B Q4       | vision+tools ★最推奨  | 3.4GB" "ON"
    "gemma3:4b-it-q4_K_M"                     "[G3]  Gemma3 4B Q4         | バランス優秀         | ~2.6GB" "OFF"
    "gemma3:1b-it-q5_K_M"                     "[G3]  Gemma3 1B Q5         | 超軽量               | ~0.8GB" "OFF"
    "llama3.2:3b-instruct-q4_K_M"             "[META] Llama3.2 3B Q4      | 英語汎用             | 2.0GB" "OFF"
    "deepseek-r1:1.5b-qwen-distill-q5_K_M"   "[R1] DeepSeek-R1 1.5B Q5   | 推論特化・軽量       | ~1.2GB" "OFF"
    "mistral:7b-instruct-v0.3-q4_K_M"         "[MIS] Mistral 7B Q4        | 汎用・安定           | 4.1GB" "OFF"
    "LFM-2.5"                                  "[LFM] LFM-2.5 Thinking Q4  | SSM省メモリ・125K ctx | 731MB" "OFF"
    "LFM-2.5-JP"                               "[LFM] LFM-2.5 日本語        | 日本語特化SSM        | ~0.7GB" "OFF"
  )

  local selected
  selected=$(ui_checklist "ダウンロードするモデルを選択 (スペースで選択)" "${items[@]}") || return

  if [ -z "$selected" ]; then
    ui_msg "情報" "モデルが選択されませんでした"
    return
  fi

  # API pull モデルと LFM-2.5 を分離
  local failed=()
  local lfm_requested=false
  local lfm_jp_requested=false

  for model in $selected; do
    model=$(echo "$model" | tr -d '"')

    if [ "$model" = "LFM-2.5" ]; then
      lfm_requested=true
      continue
    fi
    if [ "$model" = "LFM-2.5-JP" ]; then
      lfm_jp_requested=true
      continue
    fi

    ui_info "pull中: $model\n\nOllama API 経由でダウンロード中..."
    local logfile="/tmp/pull_setup_$$.log"
    local last_status
    last_status=$(curl -s -X POST http://localhost:11434/api/pull \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$model\"}" \
      2>&1 | tee "$logfile" | python3 -c "
import sys, json
last = ''
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        last = d.get('status', '')
        if 'error' in d:
            last = 'error: ' + d['error']
    except:
        pass
print(last)" 2>/dev/null || echo "error")
    rm -f "$logfile"
    [ "$last_status" != "success" ] && failed+=("$model")
  done

  # LFM-2.5 (Thinking): バイナリアップグレード → API pull → GGUF フォールバック
  if [ "$lfm_requested" = true ]; then
    clear
    bash "$SCRIPT_DIR/setup/06_setup_lfm.sh"
    press_any_key
  fi

  # LFM-2.5 日本語: バイナリアップグレード済み前提でAPI pull
  if [ "$lfm_jp_requested" = true ]; then
    ui_info "LFM-2.5 日本語モデルをpull中...\n(nn-tsuzu/LFM2.5-1.2B-JP)"
    local logfile="/tmp/pull_lfm_jp_$$.log"
    local last_status
    last_status=$(curl -s -X POST http://localhost:11434/api/pull \
      -H "Content-Type: application/json" \
      -d '{"name": "nn-tsuzu/LFM2.5-1.2B-JP"}' \
      2>&1 | tee "$logfile" | python3 -c "
import sys, json
last = ''
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        last = d.get('status', '')
        if 'error' in d: last = 'error: ' + d['error']
    except: pass
print(last)" 2>/dev/null || echo "error")
    rm -f "$logfile"
    if [ "$last_status" != "success" ]; then
      ui_error "LFM-2.5 日本語モデルのpullに失敗しました。\n先に LFM-2.5 (setup/06_setup_lfm.sh) を実行してバイナリを更新してください。"
    fi
  fi

  # 最終結果
  local installed
  installed=$(curl -s http://localhost:11434/api/tags 2>/dev/null | \
    python3 -c "import sys,json; [print(' •', m['name']) for m in json.load(sys.stdin).get('models',[])]" \
    2>/dev/null || echo "  (取得失敗)")

  if [ ${#failed[@]} -eq 0 ]; then
    ui_success "セットアップ完了！\n\nインストール済みモデル:\n$installed\n\n次のステップ:\n  ./ollama-run.sh qwen2.5:3b  # インタラクティブチャット\n  bash menu.sh → 3. Service   # サービス管理"
  else
    ui_error "以下のモデルのダウンロードに失敗しました:\n${failed[*]}\n\nインストール済み:\n$installed"
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

