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
  # LFM-2.5 は Ollama API では pull 不可 (古いバージョン) → GGUF インポートで別処理
  local items=(
    "qwen2.5:3b"  "Qwen2.5 3B   | 軽量日本語       | ~2.0GB" "ON"
    "qwen2.5:7b"  "Qwen2.5 7B   | 日本語最強クラス | ~4.5GB" "OFF"
    "gemma2:2b"   "Gemma 2 2B   | 超軽量バックアップ| ~1.8GB" "OFF"
    "phi3.5:mini" "Phi-3.5 Mini | コード生成       | ~2.4GB" "OFF"
    "llama3.2:3b" "Llama 3.2 3B | 英語汎用         | ~2.2GB" "OFF"
    "mistral:7b"  "Mistral 7B   | 汎用・品質高     | ~4.1GB" "OFF"
    "LFM-2.5"     "LFM-2.5 1.2B | SSM軽量 (GGUF)  | ~0.7GB" "OFF"
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

  for model in $selected; do
    model=$(echo "$model" | tr -d '"')

    if [ "$model" = "LFM-2.5" ]; then
      lfm_requested=true
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

  # LFM-2.5: GGUF インポート (HuggingFace からダウンロード → /api/create)
  if [ "$lfm_requested" = true ]; then
    clear
    bash "$SCRIPT_DIR/setup/06_setup_lfm.sh"
    press_any_key
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

