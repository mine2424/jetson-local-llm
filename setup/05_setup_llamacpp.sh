#!/bin/bash
# setup/05_setup_llamacpp.sh - llama.cpp ビルド (Jetson CUDA対応)
#
# 目的:
#   LFM-2.5 など Ollama で動かせないモデルを
#   llama-server (OpenAI互換 API) として port 8081 で提供するためのビルド
#
# Jetson Orin Nano Super:
#   CUDA Architecture: sm_87 (Ampere)
#   aarch64 (ARM64) → バイナリ配布が使えないためソースビルド必須

set -e

LLAMACPP_DIR="$HOME/llama.cpp"
BUILD_DIR="$LLAMACPP_DIR/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

echo ""
echo "══════════════════════════════════════════════════════"
echo "  🔨 llama.cpp ビルド (Jetson Orin Nano Super)"
echo "  CUDA Architecture: sm_87 / aarch64"
echo "══════════════════════════════════════════════════════"
echo ""

# ─── 前提チェック ──────────────────────────────────────────────────────────────
echo "── [1/4] 前提確認 ──"

# cmake
if ! command -v cmake &>/dev/null; then
  info "cmake をインストール中..."
  sudo apt-get update -y && sudo apt-get install -y cmake build-essential
fi
ok "cmake: $(cmake --version | head -1)"

# CUDA (nvcc)
if command -v nvcc &>/dev/null; then
  ok "CUDA: $(nvcc --version | grep release | awk '{print $5}' | tr -d ',')"
  USE_CUDA=ON
else
  info "nvcc が見つかりません。CPU のみビルドします"
  USE_CUDA=OFF
fi

# curl (llama-cli -hf に必要)
sudo apt-get install -y libcurl4-openssl-dev 2>/dev/null || true

# ─── クローン / 更新 ────────────────────────────────────────────────────────────
echo ""
echo "── [2/4] リポジトリ取得 ──"

if [ -d "$LLAMACPP_DIR" ]; then
  ok "既存リポジトリ: $LLAMACPP_DIR"
  info "最新コミットに更新中..."
  cd "$LLAMACPP_DIR" && git pull --ff-only 2>/dev/null || true
else
  info "クローン中: https://github.com/ggml-org/llama.cpp"
  git clone --depth=1 https://github.com/ggml-org/llama.cpp "$LLAMACPP_DIR"
fi
ok "リポジトリ取得完了"

# ─── ビルド ─────────────────────────────────────────────────────────────────────
echo ""
echo "── [3/4] CMake ビルド (CUDA=$USE_CUDA) ──"
echo "  ⏱️  初回は 10〜20 分かかります"
cd "$LLAMACPP_DIR"

cmake -B "$BUILD_DIR" \
  -DGGML_CUDA="$USE_CUDA" \
  -DCMAKE_CUDA_ARCHITECTURES=87 \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_CURL=ON \
  2>&1 | tail -5

cmake --build "$BUILD_DIR" --config Release -j "$(nproc)" 2>&1 | tail -10

# ─── バイナリ確認 ───────────────────────────────────────────────────────────────
echo ""
echo "── [4/4] バイナリ確認 ──"

for bin in llama-cli llama-server; do
  if [ -f "$BUILD_DIR/bin/$bin" ]; then
    ok "$bin: $BUILD_DIR/bin/$bin"
  else
    err "$bin: ビルドに失敗しました"
    exit 1
  fi
done

# PATH 設定
SHELL_RC="$HOME/.bashrc"
if ! grep -q "llama.cpp/build/bin" "$SHELL_RC" 2>/dev/null; then
  echo "" >> "$SHELL_RC"
  echo "# llama.cpp" >> "$SHELL_RC"
  echo "export PATH=\"$BUILD_DIR/bin:\$PATH\"" >> "$SHELL_RC"
  ok "PATH を $SHELL_RC に追加しました"
fi
export PATH="$BUILD_DIR/bin:$PATH"

echo ""
echo "══════════════════════════════════════════════════════"
ok "llama.cpp ビルド完了"
echo "══════════════════════════════════════════════════════"
echo ""
echo "  バイナリ:"
echo "    llama-cli    → CUI チャット"
echo "    llama-server → OpenAI互換 APIサーバ"
echo ""
echo "  次のステップ:"
echo "    bash setup/06_setup_lfm.sh   # LFM-2.5 セットアップ"
echo ""
