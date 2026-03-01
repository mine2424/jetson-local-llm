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

    local mem_used mem_total
    mem_used=$(free -h | awk '/^Mem/{print $3}')
    mem_total=$(free -h | awk '/^Mem/{print $2}')

    local status_line="Ollama: $ollama_status  |  モデル: ${model_count}件  |  RAM: $mem_used / $mem_total"

    local choice
    choice=$(whiptail \
      --title "🤖 Jetson Local LLM" \
      --menu "$status_line\n\nメニューを選択:" \
      $HEIGHT $WIDTH 8 \
      "1" "⚙️  Setup        - 環境構築・インストール" \
      "2" "📦 Models       - モデル管理 (pull / import / delete)" \
      "3" "🚀 Service      - サービス管理 (Ollama / WebUI)" \
      "4" "⚡ Benchmark    - 性能計測" \
      "5" "📖 Docs         - ドキュメントを開く" \
      "Q" "🚪 終了" \
      3>&1 1>&2 2>&3) || break

    case "$choice" in
      1) menu_setup ;;
      2) menu_models ;;
      3) menu_service ;;
      4) menu_bench ;;
      5) menu_docs ;;
      Q) break ;;
    esac
  done

  clear
  echo "👋 Jetson Local LLM を終了しました"
}

menu_docs() {
  local choice
  choice=$(ui_menu "📖 ドキュメント" \
    "1" "🚀 クイックスタート - Ollama起動 & テスト" \
    "2" "📋 モデル一覧" \
    "3" "🔧 LFM-2.5 セットアップ" \
    "4" "🌐 LFM-2.5 日本語モデル調査" \
    "5" "📡 API 使い方 (Python/TypeScript)" \
    "6" "🆘 トラブルシューティング" \
    "B" "← 戻る"
  ) || return

  local doc_map=(
    ""                                  # dummy for index 0
    "docs/quickstart.md"
    "models/model_list.md"
    "docs/lfm25_setup.md"
    "docs/lfm25_japanese.md"
    "docs/api_usage.md"
    "docs/troubleshooting.md"
  )

  [[ "$choice" == "B" ]] && return

  local doc_file="$SCRIPT_DIR/${doc_map[$choice]}"

  if [ -f "$doc_file" ]; then
    whiptail --title "$TITLE - ドキュメント" \
      --scrolltext \
      --textbox "$doc_file" $HEIGHT $WIDTH
  else
    ui_error "ファイルが見つかりません:\n$doc_file"
  fi
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
