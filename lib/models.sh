#!/bin/bash
# lib/models.sh - モデル管理メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

# 推奨モデル定義 (全て量子化済み・3B以上はQ4_K_M必須)
# フォーマット: "カテゴリ | 説明 | サイズ"
declare -A RECOMMENDED_MODELS
RECOMMENDED_MODELS=(
  # LFM-2.5 (要: setup/06_setup_lfm.sh でバイナリアップグレード済み)
  ["lfm2.5-thinking:1.2b-q4_K_M"]="[LFM] LFM-2.5 Thinking Q4    | SSM省メモリ・125K ctx | 731MB"
  ["lfm2.5-thinking:1.2b-q8_0"]="[LFM] LFM-2.5 Thinking Q8    | SSM高品質版           | 1.2GB"
  ["nn-tsuzu/LFM2.5-1.2B-JP"]="[LFM] LFM-2.5 日本語fine-tune | 日本語特化SSM         | ~0.7GB"
  # Qwen2.5 (日本語最強)
  ["qwen2.5:1.5b-instruct-q5_K_M"]="[JA]  Qwen2.5 1.5B Q5         | 超軽量日本語          | ~1.1GB"
  ["qwen2.5:3b-instruct-q4_K_M"]="[JA]  Qwen2.5 3B Q4            | 軽量日本語 ★推奨      | 1.9GB"
  ["qwen2.5:7b-instruct-q4_K_M"]="[JA]  Qwen2.5 7B Q4            | 日本語最高性能 ★推奨  | 4.7GB"
  # Qwen2.5-Coder
  ["qwen2.5-coder:3b-instruct-q4_K_M"]="[CODE] Qwen2.5-Coder 3B Q4  | コード軽量 ★推奨      | 1.9GB"
  ["qwen2.5-coder:7b-instruct-q4_K_M"]="[CODE] Qwen2.5-Coder 7B Q4  | コード高性能          | 4.7GB"
  # Qwen3 (最新世代 2025)
  ["qwen3:1.7b-q5_K_M"]="[NEW] Qwen3 1.7B Q5            | 最新・推論機能付き軽量 | ~1.3GB"
  ["qwen3:4b-q4_K_M"]="[NEW] Qwen3 4B Q4              | 最新・高性能 ★推奨    | ~2.6GB"
  # Gemma 3
  ["gemma3:1b-it-q5_K_M"]="[G3]  Gemma3 1B Q5             | 超軽量・優秀          | ~0.8GB"
  ["gemma3:4b-it-q4_K_M"]="[G3]  Gemma3 4B Q4             | バランス優秀 ★推奨    | ~2.6GB"
  # Llama 3.2
  ["llama3.2:1b-instruct-q5_K_M"]="[META] Llama3.2 1B Q5         | 超軽量                | ~0.7GB"
  ["llama3.2:3b-instruct-q4_K_M"]="[META] Llama3.2 3B Q4         | 英語汎用              | 2.0GB"
  # DeepSeek-R1 (推論特化)
  ["deepseek-r1:1.5b-qwen-distill-q5_K_M"]="[R1] DeepSeek-R1 1.5B Q5    | 推論特化・軽量        | ~1.2GB"
  ["deepseek-r1:7b-qwen-distill-q4_K_M"]="[R1] DeepSeek-R1 7B Q4      | 推論特化・高性能      | 4.7GB"
  # Mistral
  ["mistral:7b-instruct-v0.3-q4_K_M"]="[MIS] Mistral 7B Q4           | 汎用・安定            | 4.1GB"
)

menu_models() {
  while true; do
    # Ollama 起動確認
    if ! check_ollama; then
      if ui_confirm "⚠️ Ollamaが起動していません。\nDockerコンテナを起動しますか？"; then
        _start_ollama_docker
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

# Ollama Docker コンテナを起動
_start_ollama_docker() {
  ui_info "Ollama (Docker) を起動中...\nページキャッシュを解放してGPUメモリを確保します"
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
  sudo docker start ollama > /dev/null 2>&1 || true
  sleep 3
  if check_ollama; then
    ui_success "Ollama が起動しました"
  else
    ui_error "起動に失敗しました\nログ: sudo docker logs ollama"
  fi
}

# API 経由でモデルをpull (NDJSON ストリーム → 最終ステータス確認)
_api_pull() {
  local model="$1"
  local logfile="$2"
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
print(last)
" 2>/dev/null || echo "error")
  [ "$last_status" = "success" ]
}

_model_list() {
  local models
  models=$(get_models)

  if [ -z "$models" ]; then
    ui_msg "モデル一覧" "インストール済みのモデルはありません。\n\nまずモデルをpullしてください。"
    return
  fi

  local report="インストール済みモデル:\n\n"
  local disk_usage
  disk_usage=$(du -sh ~/.ollama/models 2>/dev/null | cut -f1)
  report+="合計ディスク使用量: ${disk_usage:-不明}\n\n"

  while IFS= read -r model; do
    report+="  • $model\n"
  done <<< "$models"

  # 実行中モデル (API /api/ps)
  local running
  running=$(curl -s http://localhost:11434/api/ps 2>/dev/null | \
    python3 -c "
import sys, json
try:
    for m in json.load(sys.stdin).get('models', []):
        size_mb = m.get('size_vram', 0) // 1048576
        print(f\"  {m['name']}  ({size_mb}MB VRAM)\")
except:
    pass
" 2>/dev/null || true)
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

  local failed=()
  for model in $selected; do
    model=$(echo "$model" | tr -d '"')
    ui_info "pull中: $model\n\nOllama API 経由でダウンロード中..."
    local logfile="/tmp/pull_$$.log"
    if ! _api_pull "$model" "$logfile"; then
      failed+=("$model")
    fi
    rm -f "$logfile"
  done

  if [ ${#failed[@]} -eq 0 ]; then
    ui_success "すべてのモデルのダウンロードが完了しました！\n\n$(get_models)"
  else
    ui_error "以下のモデルのダウンロードに失敗しました:\n${failed[*]}\n\nLFM-2.5はOllamaに未対応の場合があります。\ndocs/lfm25_setup.md を参照してください。"
  fi
}

_model_pull_all() {
  ui_confirm "推奨モデルを全てダウンロードします。\n合計 10〜15GB 必要です。続けますか？" || return

  local failed=()
  for model in "${!RECOMMENDED_MODELS[@]}"; do
    ui_info "pull中: $model\n\nOllama API 経由でダウンロード中..."
    local logfile="/tmp/pull_all_$$.log"
    if ! _api_pull "$model" "$logfile"; then
      failed+=("$model")
    fi
    rm -f "$logfile"
  done

  if [ ${#failed[@]} -eq 0 ]; then
    ui_success "推奨モデルのダウンロードが完了しました\n\n$(get_models)"
  else
    ui_error "以下のモデルのダウンロードに失敗しました:\n${failed[*]}"
  fi
}

_model_pull_custom() {
  local model_name
  model_name=$(ui_input "Ollamaモデル名を入力 (例: qwen2.5:14b, codellama:7b)" "") || return
  [ -z "$model_name" ] && return

  ui_info "pull中: $model_name ..."
  local logfile="/tmp/pull_custom_$$.log"
  if _api_pull "$model_name" "$logfile"; then
    rm -f "$logfile"
    ui_success "$model_name のダウンロードが完了しました！"
  else
    rm -f "$logfile"
    ui_error "$model_name のダウンロードに失敗しました。\nモデル名が正しいか確認してください。"
  fi
}

_model_import_gguf() {
  # GGUFファイルは ~/ .ollama/models/ 以下に置く必要がある
  # (コンテナマウント: ~/.ollama/models → /data/models/ollama/models)
  whiptail --title "$TITLE - GGUF インポート" \
    --msgbox "GGUFファイルのインポートについて\n\n【重要】ファイルは以下のパスに置く必要があります:\n  ~/.ollama/models/ 以下\n\n理由: Ollamaコンテナはこのディレクトリのみマウントされており、\nコンテナ内パス /data/models/ollama/models/ に対応します。\n\n例: ~/.ollama/models/imports/mymodel.gguf\n    → コンテナ内: /data/models/ollama/models/imports/mymodel.gguf" \
    $HEIGHT $WIDTH

  local gguf_path
  gguf_path=$(ui_input "GGUFファイルのパスを入力\n(~/.ollama/models/ 以下)" "$HOME/.ollama/models/") || return
  [ -z "$gguf_path" ] && return

  if [ ! -f "$gguf_path" ]; then
    ui_error "ファイルが見つかりません:\n$gguf_path"
    return
  fi

  # パスのバリデーション: ~/.ollama/models/ 以下であること
  local models_base="$HOME/.ollama/models"
  if [[ "$gguf_path" != "$models_base/"* ]]; then
    ui_error "ファイルは ~/.ollama/models/ 以下に置いてください\n\n指定されたパス:\n$gguf_path"
    return
  fi

  # コンテナ内パスに変換
  local relative_path="${gguf_path#$models_base/}"
  local container_path="/data/models/ollama/models/$relative_path"

  local model_name
  model_name=$(ui_input "Ollamaでのモデル名を入力" "$(basename "$gguf_path" .gguf)") || return
  [ -z "$model_name" ] && return

  # Modelfile を生成してAPIでcreate
  local modelfile_content
  modelfile_content="FROM $container_path

PARAMETER num_ctx 8192
PARAMETER temperature 0.7
PARAMETER stop \"<|im_end|>\""

  ui_info "$model_name をインポート中...\n(大きいファイルは数分かかります)"

  local response
  response=$(python3 -c "
import json, sys
modelfile = '''$modelfile_content'''
payload = json.dumps({'name': '$model_name', 'modelfile': modelfile, 'stream': False})
print(payload)
" | curl -s -X POST http://localhost:11434/api/create \
    -H "Content-Type: application/json" \
    -d @- 2>&1)

  local status
  status=$(echo "$response" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print(d.get('status', 'error'))
except:
    print('error')
" 2>/dev/null || echo "error")

  if [ "$status" = "success" ]; then
    ui_success "インポート完了！\n\nモデル名: $model_name\n\nAPI経由で使用可能です"
  else
    ui_error "インポートに失敗しました。\n\nレスポンス: $response"
  fi
}

_model_remove() {
  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_msg "情報" "削除できるモデルがありません"
    return
  fi

  local items=()
  while IFS= read -r m; do
    items+=("$m" "$m")
  done <<< "$models"

  local target
  target=$(ui_menu "🗑️  削除するモデルを選択" "${items[@]}") || return

  ui_confirm "⚠️ $target を削除しますか？\n(この操作は元に戻せません)" || return

  local response
  response=$(curl -s -X DELETE http://localhost:11434/api/delete \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$target\"}" 2>&1)

  # 削除成功は HTTP 200 で空レスポンス
  if [ -z "$response" ] || echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(1 if 'error' in d else 0)" 2>/dev/null; then
    ui_success "$target を削除しました"
  else
    ui_error "$target の削除に失敗しました\n\n$response"
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
  cuda_memfree

  local result
  result=$(curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json; print(json.dumps({'model': '$target', 'prompt': '$prompt', 'stream': False}))")" \
    2>&1 | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'error' in d:
        print('エラー: ' + d['error'])
    else:
        print(d.get('response', '(応答なし)'))
except Exception as e:
    print(f'パースエラー: {e}')
" 2>&1)

  whiptail --title "$TITLE - $target の応答" \
    --scrolltext \
    --msgbox "$result" $HEIGHT $WIDTH
}
