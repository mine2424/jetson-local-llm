#!/bin/bash
# setup/12_setup_qwen35_gguf.sh - Qwen3.5 GGUF モデルダウンロード (llama.cpp 用)
#
# HuggingFace から Qwen3.5 の GGUF ファイルをダウンロードして
# llama-server で使用可能にする。
#
# ⚠️ Qwen3-Coder (30B-A3B / 80B-A3B) は最小 Q4 でも 19GB+ → Jetson 8GB 不可
#    Qwen3.5 自体が vision + tools + thinking + agentic coding 対応なので
#    コーディング用途でも十分実用的。

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

GGUF_DIR="$HOME/.ollama/models/qwen35_gguf"

# モデル定義: "表示名|HFリポ|ファイル名|サイズ"
declare -a MODELS=(
  "Qwen3.5 0.8B Q4_K_M (0.6GB)|unsloth/Qwen3.5-0.8B-GGUF|Qwen3.5-0.8B-Q4_K_M.gguf"
  "Qwen3.5 0.8B Q8_0   (0.9GB)|unsloth/Qwen3.5-0.8B-GGUF|Qwen3.5-0.8B-Q8_0.gguf"
  "Qwen3.5 2B Q4_K_M   (1.3GB)|unsloth/Qwen3.5-2B-GGUF|Qwen3.5-2B-Q4_K_M.gguf"
  "Qwen3.5 2B Q8_0     (2.0GB)|unsloth/Qwen3.5-2B-GGUF|Qwen3.5-2B-Q8_0.gguf"
  "Qwen3.5 4B Q4_K_M   (2.9GB)|bartowski/Qwen_Qwen3.5-4B-GGUF|Qwen3.5-4B-Q4_K_M.gguf"
  "Qwen3.5 4B Q8_0     (4.5GB)|bartowski/Qwen_Qwen3.5-4B-GGUF|Qwen3.5-4B-Q8_0.gguf"
)

echo ""
echo "══════════════════════════════════════════════════════"
echo "  📦 Qwen3.5 GGUF ダウンロード (llama.cpp 用)"
echo "══════════════════════════════════════════════════════"
echo ""
echo "  保存先: $GGUF_DIR"
echo ""
echo "  ⚠️  Qwen3-Coder は最小 19GB → Jetson 8GB では不可"
echo "  Qwen3.5 は coding + tools + thinking 対応で代替可能"
echo ""

# ─── [1/3] 前提チェック ──────────────────────────────────────────────────────
echo "── [1/3] 前提チェック ──"

if ! python3 -c "import huggingface_hub" 2>/dev/null; then
  info "huggingface_hub をインストール中..."
  pip3 install --user huggingface_hub 2>/dev/null || pip3 install huggingface_hub
fi
ok "huggingface_hub: 利用可能"

mkdir -p "$GGUF_DIR"
ok "保存先: $GGUF_DIR"

# ─── [2/3] モデル選択 ────────────────────────────────────────────────────────
echo ""
echo "── [2/3] ダウンロードするモデルを選択 ──"
echo ""

declare -a SELECTED=()

for i in "${!MODELS[@]}"; do
  IFS='|' read -r display repo filename <<< "${MODELS[$i]}"
  local_path="$GGUF_DIR/$filename"

  if [ -f "$local_path" ]; then
    echo "  [$((i+1))] $display  ✅ ダウンロード済み"
  else
    echo "  [$((i+1))] $display"
  fi
done

echo ""
echo "  [A] すべてダウンロード (推奨: 2B Q8 + 4B Q4)"
echo "  [R] 推奨セット (2B-Q8_0 + 4B-Q4_K_M)"
echo "  [Q] キャンセル"
echo ""
read -rp "  番号を入力 (カンマ区切りで複数可, 例: 3,5): " choice

case "$choice" in
  [Qq]) echo "キャンセルしました"; exit 0 ;;
  [Aa]) SELECTED=("${!MODELS[@]}") ;;
  [Rr]) SELECTED=(3 4) ;;  # 2B-Q8_0 (index 3) + 4B-Q4_K_M (index 4)
  *)
    IFS=',' read -ra nums <<< "$choice"
    for n in "${nums[@]}"; do
      n=$(echo "$n" | tr -d ' ')
      if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#MODELS[@]}" ]; then
        SELECTED+=($((n-1)))
      fi
    done
    ;;
esac

if [ ${#SELECTED[@]} -eq 0 ]; then
  err "モデルが選択されませんでした"
  exit 1
fi

# ─── [3/3] ダウンロード ──────────────────────────────────────────────────────
echo ""
echo "── [3/3] ダウンロード中 ──"

FAILED=()
for idx in "${SELECTED[@]}"; do
  IFS='|' read -r display repo filename <<< "${MODELS[$idx]}"
  local_path="$GGUF_DIR/$filename"

  if [ -f "$local_path" ]; then
    ok "$filename: 既にダウンロード済み ($(du -h "$local_path" | cut -f1))"
    continue
  fi

  echo ""
  info "$display をダウンロード中..."
  info "  リポ: $repo"
  info "  ファイル: $filename"

  if python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(
    repo_id='$repo',
    filename='$filename',
    local_dir='$GGUF_DIR',
    local_dir_use_symlinks=False
)
print('OK')
" 2>&1; then
    if [ -f "$local_path" ]; then
      ok "$filename ダウンロード完了 ($(du -h "$local_path" | cut -f1))"
    else
      # huggingface_hub がサブディレクトリに配置する場合がある
      found=$(find "$GGUF_DIR" -name "$filename" -type f 2>/dev/null | head -1)
      if [ -n "$found" ] && [ "$found" != "$local_path" ]; then
        mv "$found" "$local_path"
        ok "$filename ダウンロード完了 ($(du -h "$local_path" | cut -f1))"
      else
        err "$filename: ダウンロード後にファイルが見つかりません"
        FAILED+=("$filename")
      fi
    fi
  else
    err "$filename のダウンロードに失敗しました"
    FAILED+=("$filename")
  fi
done

# ─── 結果表示 ────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"

if [ ${#FAILED[@]} -eq 0 ]; then
  ok "ダウンロード完了！"
else
  err "失敗: ${FAILED[*]}"
fi

echo ""
echo "  保存先: $GGUF_DIR"
echo ""
echo "  使い方:"
echo "    ./menu.sh → Service → llama-server 起動"
echo "    → GGUF ファイル選択画面にモデルが表示されます"
echo ""

# 既存ファイル一覧
echo "  ダウンロード済みモデル:"
find "$GGUF_DIR" -name "*.gguf" -type f -exec sh -c 'echo "    $(du -h "$1" | cut -f1)  $(basename "$1")"' _ {} \; 2>/dev/null | sort
echo ""
echo "══════════════════════════════════════════════════════"
