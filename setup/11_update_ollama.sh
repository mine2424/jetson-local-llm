#!/bin/bash
# setup/11_update_ollama.sh - Ollama バイナリをコンテナ内で最新版に更新
#
# dustynv/ollama コンテナは Ollama 0.6.8 で止まっており、
# 新しいモデル (qwen3.5, gemma3 等) が 412 エラーで pull できない。
# このスクリプトは最新の公式 JetPack6 arm64 バイナリをダウンロードして
# コンテナ内の /usr/local/bin/ollama を差し替える。
#
# ダウンロード構成 (公式 install.sh と同じ):
#   1. ollama-linux-arm64.tar.zst     (メインバイナリ + ランナー ~1.2GB)
#   2. ollama-linux-arm64-jetpack6.tar.zst (JetPack6 CUDA ライブラリ ~245MB)

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

CONTAINER_NAME="${1:-ollama}"

echo ""
echo "══════════════════════════════════════════════════════"
echo "  🔄 Ollama バイナリ更新 (コンテナ内)"
echo "══════════════════════════════════════════════════════"
echo ""

# ─── [1/6] 前提確認 ──────────────────────────────────────────────────────────
echo "── [1/6] 前提確認 ──"
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  err "コンテナ '${CONTAINER_NAME}' が起動していません"
  err "先に起動してください: docker start ${CONTAINER_NAME}"
  exit 1
fi

if ! command -v zstd &>/dev/null; then
  err "zstd が必要です: sudo apt install zstd"
  exit 1
fi
ok "zstd: インストール済み"

CURRENT_VER=$(docker exec "$CONTAINER_NAME" ollama --version 2>/dev/null | awk '{print $NF}')
ok "現在のバージョン: ${CURRENT_VER:-不明}"

# ─── [2/6] 最新バージョン取得 ────────────────────────────────────────────────
echo ""
echo "── [2/6] 最新バージョン確認 ──"

LATEST_VER=$(curl -sI https://github.com/ollama/ollama/releases/latest 2>/dev/null \
  | grep -i '^location:' | sed 's|.*/v||; s/\r//')

if [ -z "$LATEST_VER" ]; then
  err "最新バージョンの取得に失敗しました"
  exit 1
fi
ok "最新バージョン: v${LATEST_VER}"

if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
  ok "既に最新版です。更新不要。"
  exit 0
fi

info "v${CURRENT_VER:-?} → v${LATEST_VER} に更新します"

# ─── [3/6] メインバイナリダウンロード & 展開 ─────────────────────────────────
echo ""
echo "── [3/6] メインバイナリをダウンロード中 (~1.2GB) ──"

TMPDIR=$(mktemp -d)
INSTALL_DIR="${TMPDIR}/install"
mkdir -p "$INSTALL_DIR"

BASE_URL="https://github.com/ollama/ollama/releases/download/v${LATEST_VER}"

info "ollama-linux-arm64.tar.zst をダウンロード & 展開中..."
if ! curl -fL --progress-bar "${BASE_URL}/ollama-linux-arm64.tar.zst" | zstd -d | tar -xf - -C "$INSTALL_DIR"; then
  err "メインバイナリのダウンロードに失敗しました"
  rm -rf "$TMPDIR"
  exit 1
fi
ok "メインバイナリ展開完了"

# ─── [4/6] JetPack6 CUDA ライブラリ ──────────────────────────────────────────
echo ""
echo "── [4/6] JetPack6 CUDA ライブラリをダウンロード中 (~245MB) ──"

info "ollama-linux-arm64-jetpack6.tar.zst をダウンロード & 展開中..."
if curl -fL --progress-bar "${BASE_URL}/ollama-linux-arm64-jetpack6.tar.zst" | zstd -d | tar -xf - -C "$INSTALL_DIR"; then
  ok "JetPack6 ライブラリ展開完了"
else
  info "JetPack6 ライブラリのダウンロードに失敗 (メインバイナリのみで続行)"
fi

# 展開結果を確認
OLLAMA_BIN="${INSTALL_DIR}/bin/ollama"
if [ ! -f "$OLLAMA_BIN" ]; then
  # bin/ にない場合は find
  OLLAMA_BIN=$(find "$INSTALL_DIR" -name ollama -type f | head -1)
fi

if [ -z "$OLLAMA_BIN" ] || [ ! -f "$OLLAMA_BIN" ]; then
  err "ollama バイナリが見つかりません"
  info "展開内容:"
  find "$INSTALL_DIR" -maxdepth 3 -type f | head -20
  rm -rf "$TMPDIR"
  exit 1
fi
chmod +x "$OLLAMA_BIN"
ok "ollama バイナリ: $(du -h "$OLLAMA_BIN" | cut -f1)"

# ─── [5/6] コンテナ内にコピー ────────────────────────────────────────────────
echo ""
echo "── [5/6] コンテナ内にコピー ──"

# 既存バイナリをバックアップ
docker exec "$CONTAINER_NAME" cp /usr/local/bin/ollama /usr/local/bin/ollama.bak 2>/dev/null || true

# メインバイナリをコピー
docker cp "$OLLAMA_BIN" "${CONTAINER_NAME}:/usr/local/bin/ollama"
ok "ollama バイナリをコピー完了"

# lib/ ディレクトリをコピー (ランナー + CUDA ライブラリ)
if [ -d "${INSTALL_DIR}/lib" ]; then
  info "ライブラリをコピー中..."
  docker exec "$CONTAINER_NAME" mkdir -p /usr/local/lib 2>/dev/null || true
  docker cp "${INSTALL_DIR}/lib/." "${CONTAINER_NAME}:/usr/local/lib/" 2>/dev/null || true
  ok "ライブラリをコピー完了"
fi

rm -rf "$TMPDIR"

# ─── [6/6] Ollama サーバ再起動 ────────────────────────────────────────────────
echo ""
echo "── [6/6] Ollama サーバ再起動 ──"

docker restart "$CONTAINER_NAME"
info "コンテナ再起動中..."

# API 応答待機
for i in $(seq 1 15); do
  if curl -s http://localhost:11434/api/version > /dev/null 2>&1; then
    NEW_VER=$(curl -s http://localhost:11434/api/version 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")
    echo ""
    echo "══════════════════════════════════════════════════════"
    ok "Ollama 更新完了！"
    echo "══════════════════════════════════════════════════════"
    echo ""
    echo "  v${CURRENT_VER:-?} → v${NEW_VER}"
    echo ""
    echo "  これで qwen3.5, gemma3 等の新モデルが pull 可能です"
    echo ""
    exit 0
  fi
  info "待機中... (${i}/15)"
  sleep 3
done

err "API が45秒以内に応答しませんでした"
err "ログを確認: docker logs ${CONTAINER_NAME}"
exit 1
