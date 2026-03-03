#!/bin/bash
# eval/japanese_eval.sh - M2: 日本語品質評価スクリプト
#
# 使い方:
#   bash eval/japanese_eval.sh                    # Ollama (port 11434)
#   bash eval/japanese_eval.sh llama 8081         # llama-server (port 8081)

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
info()  { echo -e "${YELLOW}[--]${NC} $*"; }
header(){ echo -e "${CYAN}$*${NC}"; }

MODE="${1:-ollama}"    # ollama | llama
PORT="${2:-11434}"
MODEL="${3:-qwen3.5:4b-q4_K_M}"

# llama-server の場合は v1/chat/completions を使う
if [ "$MODE" = "llama" ]; then
  PORT="${2:-8081}"
  BASE_URL="http://localhost:$PORT/v1"
else
  BASE_URL="http://localhost:$PORT/v1"
fi

RESULT_DIR="eval/results"
mkdir -p "$RESULT_DIR"
RESULT_FILE="$RESULT_DIR/japanese_eval_$(date +%Y%m%d_%H%M%S).md"

# API疎通確認
if ! curl -s "http://localhost:$PORT" > /dev/null 2>&1 && \
   ! curl -s "http://localhost:$PORT/health" > /dev/null 2>&1 && \
   ! curl -s "http://localhost:$PORT/api/tags" > /dev/null 2>&1; then
  echo "ERROR: API が応答しません (port $PORT)"
  exit 1
fi

# ─── 推論関数 ──────────────────────────────────────────────────────────────────
call_llm() {
  local system_prompt="$1"
  local user_prompt="$2"
  local timeout="${3:-60}"

  curl -s --max-time "$timeout" \
    "$BASE_URL/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json, sys
payload = {
  'model': '$MODEL',
  'messages': [
    {'role': 'system', 'content': '''$system_prompt'''},
    {'role': 'user', 'content': '''$user_prompt'''}
  ],
  'temperature': 0.1,
  'max_tokens': 500
}
print(json.dumps(payload))
")" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'])
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null
}

# ─── テスト定義 ────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo "  📝 日本語品質評価 (M2)"
echo "  モデル: $MODEL | ポート: $PORT"
echo "════════════════════════════════════════════════════"
echo ""

cat > "$RESULT_FILE" << EOF
# 日本語品質評価レポート

- **日時**: $(date '+%Y-%m-%d %H:%M:%S')
- **モデル**: $MODEL
- **API**: $BASE_URL

---
EOF

PASS=0
TOTAL=0

run_test() {
  local test_name="$1"
  local system="$2"
  local input="$3"
  local expected_hint="$4"

  TOTAL=$((TOTAL + 1))
  header "[$TOTAL] $test_name"
  info "入力: $input"

  local response
  response=$(call_llm "$system" "$input" 60)
  echo "応答: $response"
  echo ""

  # 手動評価のため結果を記録
  cat >> "$RESULT_FILE" << EOF
## [$TOTAL] $test_name

**入力:**
$input

**応答:**
$response

**期待ヒント:**
$expected_hint

**評価:** [ ] 合格 / [ ] 不合格 / **メモ:**

---
EOF

  PASS=$((PASS + 1))  # 自動採点はしない（手動確認）
}

SYSTEM_PROOFREAD="あなたは日本語の校正専門家です。入力テキストの誤字・脱字・不自然な表現を修正してください。修正後のテキストのみを返してください。"
SYSTEM_UNIFY="あなたは日本語の編集者です。文章の語尾を統一してください。「〜です・ます調（敬体）」に統一して返してください。"
SYSTEM_SUMMARIZE="あなたは要約の専門家です。与えられたテキストを100文字以内で要約してください。要約のみを返してください。"
SYSTEM_BIZIFY="あなたはビジネス文書の専門家です。口語・カジュアルな表現をビジネス文書に適した表現に書き換えてください。書き換え後のテキストのみを返してください。"
SYSTEM_DETECT="あなたは日本語の校正専門家です。以下のテキストに含まれる誤字・脱字・文法的な誤りをすべてリストアップしてください。問題がなければ「問題なし」と返してください。"

# ─── テスト実行 ────────────────────────────────────────────────────────────────

run_test "誤字脱字修正（軽微）" \
  "$SYSTEM_PROOFREAD" \
  "私はきのう東京えきで友達に会いました。とても楽しかつたです。" \
  "「東京えき」→「東京駅」、「楽しかつた」→「楽しかった」を修正"

run_test "誤字脱字修正（複数箇所）" \
  "$SYSTEM_PROOFREAD" \
  "このプロジェクトはらいねん3月にかんりょうする予定です。チームのみんながいっしょけんめいとりくんでいます。" \
  "「らいねん」→「来年」、「かんりょう」→「完了」、「いっしょけんめい」→「一生懸命」"

run_test "敬体統一（常体→敬体）" \
  "$SYSTEM_UNIFY" \
  "この機能は非常に便利だ。ユーザーの作業効率が上がります。設定は簡単で、誰でも使える。" \
  "全て「〜です・ます」に統一"

run_test "要約（500文字→100文字以内）" \
  "$SYSTEM_SUMMARIZE" \
  "人工知能（AI）技術は近年急速に発展しており、様々な産業分野において革新的な変化をもたらしています。特に機械学習や深層学習の進歩により、画像認識、自然言語処理、音声認識などの分野で人間に匹敵する、あるいはそれを超える性能を発揮するシステムが開発されています。医療分野では、AIを活用した診断支援システムが導入され、がんの早期発見や新薬開発の加速に貢献しています。自動車産業では自動運転技術の開発が進み、交通事故の削減や移動の利便性向上が期待されています。一方で、AIの普及に伴いプライバシーの問題や雇用への影響など、社会的な課題も生じており、適切な規制や倫理的なガイドラインの整備が急務となっています。" \
  "AI技術の発展と医療・自動車分野への応用、および社会的課題について100文字以内にまとめる"

run_test "口語→ビジネス文書変換" \
  "$SYSTEM_BIZIFY" \
  "このバグはめちゃくちゃやばくて、早急に直さないとお客さんに超迷惑かけちゃいます。" \
  "「めちゃくちゃやばい」→「深刻な」、「超迷惑」→「多大なご不便」などに変換"

run_test "誤り検出（誤りあり）" \
  "$SYSTEM_DETECT" \
  "先日の会議でご説明しましたとおり、プロジェクトのスケジュールを見なおしました。新しいスケジュールを添付ファイルにてお送りしましたので、ご確認のほとよろしくおねがいいたします。" \
  "「ご確認のほとよろしく」→「ご確認のほど、よろしく」（「ほと」→「ほど」）"

run_test "誤り検出（誤りなし）" \
  "$SYSTEM_DETECT" \
  "お世話になっております。先日ご依頼いただきました資料が完成いたしました。添付にてお送りしますので、ご確認のほど、よろしくお願いいたします。" \
  "「問題なし」と返すこと"

# ─── 結果サマリー ──────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
ok "評価完了: $TOTAL 件"
echo ""
echo "  結果ファイル: $RESULT_FILE"
echo ""
echo "  ⚠️  自動採点はしていません。"
echo "  上記の応答を見て、各テストに合格 / 不合格 を記入してください。"
echo ""
echo "  合格基準:"
echo "    - 誤字修正: 全箇所を見落としなく修正"
echo "    - 敬体統一: 全文が統一されている"
echo "    - 要約    : 100文字以内、内容正確"
echo "    - ビジネス化: 口語表現が全て除去"
echo "    - 誤り検出: 見落とし・誤検出なし"
echo "════════════════════════════════════════════════════"
