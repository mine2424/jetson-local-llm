#!/bin/bash
# lib/bench.sh - ベンチマークメニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

RESULTS_DIR="$SCRIPT_DIR/benchmark/results"

menu_bench() {
  while true; do
    local choice
    choice=$(ui_menu "⚡ ベンチマーク" \
      "1" "🏃 クイックベンチ (全モデル・短文)" \
      "2" "🔬 単体モデルを詳細計測" \
      "3" "📊 結果を表示 (最新)" \
      "4" "📋 全結果一覧" \
      "5" "🗑️  結果を削除" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      1) _bench_quick ;;
      2) _bench_single ;;
      3) _bench_show_latest ;;
      4) _bench_list ;;
      5) _bench_clean ;;
      B) return ;;
    esac
  done
}

_bench_quick() {
  if ! check_ollama; then
    ui_error "Ollamaが起動していません"
    return
  fi

  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_error "モデルがインストールされていません"
    return
  fi

  local model_count
  model_count=$(echo "$models" | wc -l)

  ui_confirm "インストール済みの全モデル (${model_count}件) をベンチマークします。\n各モデル30秒程度かかります。続けますか？" || return

  mkdir -p "$RESULTS_DIR"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local result_file="$RESULTS_DIR/bench_${timestamp}.md"
  local prompt="Jetson Orin Nano Superでローカルモデルを動かす利点を100文字で説明してください。"

  {
    echo "# Benchmark Results"
    echo "- Date: $(date)"
    echo "- Device: Jetson Orin Nano Super"
    echo "- Prompt: $prompt"
    echo ""
    echo "| Model | tokens/sec | elapsed(ms) | tokens |"
    echo "|-------|-----------|------------|--------|"
  } > "$result_file"

  local progress=0
  local step=$((100 / model_count))

  while IFS= read -r model; do
    echo "$progress" # for gauge

    local elapsed_ms token_count tps
    local api_result
    api_result=$(curl -s -X POST http://localhost:11434/api/generate \
      -H "Content-Type: application/json" \
      -d "$(python3 -c "import json; print(json.dumps({'model': '$model', 'prompt': '$prompt', 'stream': False}))")" \
      2>/dev/null || echo '{}')

    token_count=$(echo "$api_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('eval_count',0))" 2>/dev/null || echo 0)
    elapsed_ms=$(echo "$api_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(int(d.get('eval_duration',0)/1e6))" 2>/dev/null || echo 1)
    tps=$(echo "scale=1; $token_count * 1000 / ($elapsed_ms + 1)" | bc 2>/dev/null || echo "N/A")

    echo "| $model | $tps | $elapsed_ms | $token_count |" >> "$result_file"

    progress=$((progress + step))
  done <<< "$models" | ui_gauge "ベンチマーク実行中..."

  echo "100" | ui_gauge "完了"

  # 結果表示
  whiptail --title "$TITLE - ベンチマーク結果" \
    --scrolltext \
    --textbox "$result_file" $HEIGHT $WIDTH
}

_bench_single() {
  if ! check_ollama; then
    ui_error "Ollamaが起動していません"
    return
  fi

  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_error "モデルがインストールされていません"
    return
  fi

  local items=()
  while IFS= read -r m; do
    items+=("$m" "")
  done <<< "$models"

  local target
  target=$(ui_menu "計測するモデルを選択" "${items[@]}") || return

  local n_runs
  n_runs=$(ui_menu "計測回数を選択" \
    "1" "1回 (速い)" \
    "3" "3回 (平均)" \
    "5" "5回 (精度高)" \
  ) || return

  local prompt
  prompt=$(ui_input "ベンチマーク用プロンプト" "日本語で機械学習とは何かを説明してください。") || return

  mkdir -p "$RESULTS_DIR"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local result_file="$RESULTS_DIR/bench_${target//[:\/]/_}_${timestamp}.md"

  {
    echo "# Single Model Benchmark: $target"
    echo "- Date: $(date)"
    echo "- Runs: $n_runs"
    echo "- Prompt: $prompt"
    echo ""
    echo "| Run | tokens/sec | elapsed(ms) | tokens |"
    echo "|-----|-----------|------------|--------|"
  } > "$result_file"

  local total_tps=0
  for i in $(seq 1 "$n_runs"); do
    ui_info "計測中... ($i/$n_runs)\n\nモデル: $target"

    local elapsed_ms token_count tps
    local api_result
    api_result=$(curl -s -X POST http://localhost:11434/api/generate \
      -H "Content-Type: application/json" \
      -d "$(python3 -c "import json; print(json.dumps({'model': '$target', 'prompt': '$prompt', 'stream': False}))")" \
      2>/dev/null || echo '{}')

    token_count=$(echo "$api_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('eval_count',0))" 2>/dev/null || echo 0)
    elapsed_ms=$(echo "$api_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(int(d.get('eval_duration',0)/1e6))" 2>/dev/null || echo 1)
    tps=$(echo "scale=1; $token_count * 1000 / ($elapsed_ms + 1)" | bc 2>/dev/null || echo "0")

    echo "| $i | $tps | $elapsed_ms | $token_count |" >> "$result_file"
    total_tps=$(echo "scale=1; $total_tps + $tps" | bc 2>/dev/null || echo "$total_tps")
  done

  local avg_tps
  avg_tps=$(echo "scale=1; $total_tps / $n_runs" | bc 2>/dev/null || echo "N/A")
  echo "" >> "$result_file"
  echo "**平均 tokens/sec: $avg_tps**" >> "$result_file"

  whiptail --title "$TITLE - ベンチマーク結果: $target" \
    --scrolltext \
    --textbox "$result_file" $HEIGHT $WIDTH
}

_bench_show_latest() {
  mkdir -p "$RESULTS_DIR"
  local latest
  latest=$(ls -t "$RESULTS_DIR"/*.md 2>/dev/null | head -1)

  if [ -z "$latest" ]; then
    ui_msg "情報" "ベンチマーク結果がありません。\nまずベンチマークを実行してください。"
    return
  fi

  whiptail --title "$TITLE - 最新ベンチマーク結果" \
    --scrolltext \
    --textbox "$latest" $HEIGHT $WIDTH
}

_bench_list() {
  mkdir -p "$RESULTS_DIR"
  local files
  files=$(ls -t "$RESULTS_DIR"/*.md 2>/dev/null)

  if [ -z "$files" ]; then
    ui_msg "情報" "ベンチマーク結果がありません"
    return
  fi

  local items=()
  while IFS= read -r f; do
    local basename
    basename=$(basename "$f")
    items+=("$f" "$basename")
  done <<< "$files"

  local selected
  selected=$(ui_menu "📋 結果ファイルを選択" "${items[@]}") || return

  whiptail --title "$TITLE - ベンチマーク結果" \
    --scrolltext \
    --textbox "$selected" $HEIGHT $WIDTH
}

_bench_clean() {
  mkdir -p "$RESULTS_DIR"
  local count
  count=$(ls "$RESULTS_DIR"/*.md 2>/dev/null | wc -l)

  if [ "$count" -eq 0 ]; then
    ui_msg "情報" "削除するファイルがありません"
    return
  fi

  ui_confirm "ベンチマーク結果を全て削除しますか？\n(${count}件)" || return
  rm -f "$RESULTS_DIR"/*.md
  ui_success "削除しました"
}
