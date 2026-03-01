#!/bin/bash
# lib/models.sh - モデル管理メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

# 推奨モデル定義
declare -A RECOMMENDED_MODELS
RECOMMENDED_MODELS=(
  ["qwen2.5:7b"]="Qwen2.5 7B | 日本語最強クラス | ~4.5GB"
  ["qwen2.5:3b"]="Qwen2.5 3B | 軽量日本語 | ~2.0GB"
  ["lfm2.5:3b"]="LFM-2.5 3B | SSMアーキテクチャ・省メモリ | ~2.0GB"
  ["lfm2.5:1b"]="LFM-2.5 1B | 超軽量・高速 | ~0.8GB"
  ["phi3.5:mini"]="Phi-3.5 Mini | コード生成 | ~2.4GB"
  ["llama3.2:3b"]="Llama 3.2 3B | 英語汎用 | ~2.2GB"
  ["gemma2:2b"]="Gemma 2 2B | 超軽量バックアップ | ~1.8GB"
  ["mistral:7b"]="Mistral 7B | 汎用・品質高 | ~4.1GB"
)

menu_models() {
  while true; do
    # Ollama 起動確認
    if ! check_ollama; then
      if ui_confirm "⚠️ Ollamaが起動していません。\n起動しますか？"; then
        _start_ollama_bg
      else
        return
      fi
    fi

    local choice
    choice=$(ui_menu "📦 モデル管理" \
      "1" "📋 インストール済みモデル一覧" \
      "2" "⬇️  推奨モデルをpull (選択式)" \
      "3" "⬇️  推奨モデルを全部まとめてpull" \
      "4" "🔍 モデル名を直接指定してpull" \
      "5" "📂 GGUFファイルをインポート" \
      "6" "🗑️  モデルを削除" \
      "7" "💬 モデルをテスト実行" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      1) _model_list ;;
      2) _model_pull_select ;;
      3) _model_pull_all ;;
      4) _model_pull_custom ;;
      5) _model_import_gguf ;;
      6) _model_remove ;;
      7) _model_test ;;
      B) return ;;
    esac
  done
}

_start_ollama_bg() {
  ui_info "Ollamaを起動中..."
  OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KEEP_ALIVE=5m OLLAMA_NUM_CTX=2048 \
    ollama serve > /tmp/ollama.log 2>&1 &
  sleep 3
  if check_ollama; then
    ui_success "Ollama が起動しました"
  else
    ui_error "起動に失敗しました\nログ: /tmp/ollama.log"
  fi
}

_model_list() {
  local models
  models=$(get_models)

  if [ -z "$models" ]; then
    ui_msg "モデル一覧" "インストール済みのモデルはありません。\n\nまずモデルをpullしてください。"
    return
  fi

  # メモリ情報も付加
  local report="インストール済みモデル:\n\n"
  local disk_usage
  disk_usage=$(du -sh ~/.ollama/models 2>/dev/null | cut -f1)
  report+="合計ディスク使用量: ${disk_usage:-不明}\n\n"

  while IFS= read -r model; do
    local size
    size=$(ollama show "$model" 2>/dev/null | grep "parameter size" | awk '{print $NF}' || echo "?")
    report+="  • $model\n"
  done <<< "$models"

  # 実行中モデルも表示
  local running
  running=$(ollama ps 2>/dev/null | tail -n +2)
  if [ -n "$running" ]; then
    report+="\n▶️  実行中:\n$running"
  fi

  whiptail --title "$TITLE - モデル一覧" \
    --msgbox "$report" $HEIGHT $WIDTH
}

_model_pull_select() {
  # チェックリスト形式で選択
  local items=()
  for model in "${!RECOMMENDED_MODELS[@]}"; do
    local installed="OFF"
    if get_models | grep -q "^$model"; then
      installed="ON"
    fi
    items+=("$model" "${RECOMMENDED_MODELS[$model]}" "$installed")
  done

  local selected
  selected=$(ui_checklist "ダウンロードするモデルを選択 (スペースで選択)" "${items[@]}") || return

  if [ -z "$selected" ]; then
    ui_msg "情報" "モデルが選択されませんでした"
    return
  fi

  # 選択されたモデルをpull
  local failed=()
  for model in $selected; do
    model=$(echo "$model" | tr -d '"')
    ui_info "pull中: $model\n\nこのウィンドウはしばらく動きません..."
    if ollama pull "$model" > /tmp/pull_$$.log 2>&1; then
      : # OK
    else
      failed+=("$model")
    fi
  done

  if [ ${#failed[@]} -eq 0 ]; then
    ui_success "すべてのモデルのダウンロードが完了しました！\n\n$(get_models)"
  else
    ui_error "以下のモデルのダウンロードに失敗しました:\n${failed[*]}\n\nLFM-2.5はOllamaに未対応の場合があります。\ndocs/lfm25_setup.md を参照してください。"
  fi
}

_model_pull_all() {
  ui_confirm "推奨モデルを全てダウンロードします。\n合計 10〜15GB 必要です。続けますか？" || return

  local tmpfile
  tmpfile=$(mktemp)
  ui_info "モデルをダウンロード中...\nしばらくお待ちください（完了まで数分かかります）"
  bash "$SCRIPT_DIR/setup/03_pull_models.sh" > "$tmpfile" 2>&1
  whiptail --title "$TITLE - モデル pull 結果" \
    --scrolltext \
    --textbox "$tmpfile" $HEIGHT $WIDTH
  rm -f "$tmpfile"
  ui_success "推奨モデルのダウンロードが完了しました"
}

_model_pull_custom() {
  local model_name
  model_name=$(ui_input "Ollamaモデル名を入力 (例: qwen2.5:14b, codellama:7b)" "") || return
  [ -z "$model_name" ] && return

  ui_info "pull中: $model_name ..."
  if ollama pull "$model_name" > /tmp/pull_custom.log 2>&1; then
    ui_success "$model_name のダウンロードが完了しました！"
  else
    ui_error "$model_name のダウンロードに失敗しました。\nモデル名が正しいか確認してください。"
  fi
}

_model_import_gguf() {
  local gguf_path
  gguf_path=$(ui_input "GGUFファイルのパスを入力" "$HOME/models/") || return
  [ -z "$gguf_path" ] && return

  if [ ! -f "$gguf_path" ]; then
    ui_error "ファイルが見つかりません:\n$gguf_path"
    return
  fi

  local model_name
  model_name=$(ui_input "Ollamaでのモデル名を入力" "$(basename "$gguf_path" .gguf)") || return
  [ -z "$model_name" ] && return

  # Modelfile 生成
  local modelfile_path="/tmp/Modelfile_import_$$"
  cat > "$modelfile_path" <<EOF
FROM $gguf_path

PARAMETER num_ctx 8192
PARAMETER temperature 0.7
PARAMETER stop "<|im_end|>"
EOF

  ui_info "$model_name をインポート中..."
  if ollama create "$model_name" -f "$modelfile_path" > /tmp/import.log 2>&1; then
    rm -f "$modelfile_path"
    ui_success "インポート完了！\n\nモデル名: $model_name\n\nollama run $model_name で使えます"
  else
    rm -f "$modelfile_path"
    ui_error "インポートに失敗しました。\nログ: /tmp/import.log"
  fi
}

_model_remove() {
  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_msg "情報" "削除できるモデルがありません"
    return
  fi

  # モデルリストからメニューを動的生成
  local items=()
  while IFS= read -r m; do
    items+=("$m" "$m")
  done <<< "$models"

  local target
  target=$(ui_menu "🗑️  削除するモデルを選択" "${items[@]}") || return

  ui_confirm "⚠️ $target を削除しますか？\n(この操作は元に戻せません)" || return

  if ollama rm "$target" 2>/dev/null; then
    ui_success "$target を削除しました"
  else
    ui_error "$target の削除に失敗しました"
  fi
}

_model_test() {
  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_msg "情報" "モデルがインストールされていません"
    return
  fi

  local items=()
  while IFS= read -r m; do
    items+=("$m" "")
  done <<< "$models"

  local target
  target=$(ui_menu "💬 テストするモデルを選択" "${items[@]}") || return

  local prompt
  prompt=$(ui_input "テストプロンプトを入力" "日本語で自己紹介してください。") || return
  [ -z "$prompt" ] && return

  ui_info "$target で推論中...\n(10〜30秒かかります)"
  local result
  cuda_memfree
  result=$(ollama run "$target" "$prompt" 2>&1)

  whiptail --title "$TITLE - $target の応答" \
    --scrolltext \
    --msgbox "$result" $HEIGHT $WIDTH
}
