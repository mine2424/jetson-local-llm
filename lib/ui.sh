#!/bin/bash
# lib/ui.sh - TUI共通ヘルパー (whiptail ベース)

export TITLE="🤖 Jetson Local LLM"
export WIDTH=72
export HEIGHT=20

# whiptail の存在確認
check_whiptail() {
  if ! command -v whiptail &>/dev/null; then
    echo "whiptail が見つかりません。インストールします..."
    sudo apt-get install -y whiptail
  fi
}

# --- 汎用ダイアログ ---

ui_msg() {
  # $1=タイトル, $2=メッセージ
  whiptail --title "$TITLE - $1" \
    --msgbox "$2" $HEIGHT $WIDTH
}

ui_confirm() {
  # $1=メッセージ → 0=yes, 1=no
  whiptail --title "$TITLE" \
    --yesno "$1" 10 $WIDTH
}

ui_input() {
  # $1=プロンプト, $2=デフォルト値 → 入力値を stdout に出力
  whiptail --title "$TITLE" \
    --inputbox "$1" 10 $WIDTH "$2" 3>&1 1>&2 2>&3
}

ui_info() {
  # $1=メッセージ (ノンブロッキング表示)
  whiptail --title "$TITLE" \
    --infobox "$1" 8 $WIDTH
}

ui_error() {
  whiptail --title "❌ エラー" \
    --msgbox "$1" 12 $WIDTH
}

ui_success() {
  whiptail --title "✅ 完了" \
    --msgbox "$1" 12 $WIDTH
}

# --- 進捗表示 ---
# パイプからゲージを読む: echo "50" | ui_gauge "タイトル"
ui_gauge() {
  whiptail --title "$TITLE" \
    --gauge "$1" 8 $WIDTH 0
}

# --- コマンド実行 (出力をスクロールボックスで表示) ---
ui_run_show() {
  # $1=タイトル, $2=コマンド(文字列)
  local tmpfile
  tmpfile=$(mktemp)
  eval "$2" 2>&1 | tee "$tmpfile"
  local result=${PIPESTATUS[0]}
  whiptail --title "$TITLE - $1" \
    --scrolltext \
    --textbox "$tmpfile" $HEIGHT $WIDTH
  rm -f "$tmpfile"
  return $result
}

# --- リスト選択 ---
ui_menu() {
  # $1=プロンプト, 残り=メニュー項目ペア (tag description ...)
  local prompt="$1"; shift
  whiptail --title "$TITLE" \
    --menu "$prompt" $HEIGHT $WIDTH 12 \
    "$@" \
    3>&1 1>&2 2>&3
}

ui_checklist() {
  # $1=プロンプト, 残り=項目ペア (tag description state ...)
  local prompt="$1"; shift
  whiptail --title "$TITLE" \
    --checklist "$prompt\n(スペースで選択, Enterで確定)" \
    $HEIGHT $WIDTH 12 \
    "$@" \
    3>&1 1>&2 2>&3
}

# --- Ollama 状態チェック ---
check_ollama() {
  curl -s http://localhost:11434/api/tags > /dev/null 2>&1
}

# --- モデル一覧取得 ---
get_models() {
  # インストール済みモデル名を改行区切りで返す
  if check_ollama; then
    curl -s http://localhost:11434/api/tags | \
      python3 -c "import sys,json; [print(m['name']) for m in json.load(sys.stdin)['models']]" 2>/dev/null
  fi
}

# --- ターミナルに戻るまで待機 ---
press_any_key() {
  echo ""
  echo "--- Enterキーでメニューに戻る ---"
  read -r
}
