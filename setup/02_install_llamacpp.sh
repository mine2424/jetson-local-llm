#!/bin/bash
# llama.cpp インストール (Jetson CUDA対応ビルド)
set -e

echo "=== Building llama.cpp for Jetson (CUDA) ==="

INSTALL_DIR="$HOME/llama.cpp"

# 依存関係
sudo apt-get update -y
sudo apt-get install -y cmake build-essential libcurl4-openssl-dev

# クローン or 更新
if [ -d "$INSTALL_DIR" ]; then
  echo "Updating existing llama.cpp..."
  cd "$INSTALL_DIR" && git pull
else
  git clone https://github.com/ggml-org/llama.cpp "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

# CUDA対応ビルド (Jetson Ampere = sm_87)
cmake -B build \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=87 \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --config Release -j$(nproc)

# パスを追加
SHELL_RC="$HOME/.bashrc"
if ! grep -q "llama.cpp/build/bin" "$SHELL_RC"; then
  echo "export PATH=\"$INSTALL_DIR/build/bin:\$PATH\"" >> "$SHELL_RC"
  echo "Added llama.cpp to PATH in $SHELL_RC"
fi

echo ""
echo "✅ llama.cpp built successfully"
echo "   Binary: $INSTALL_DIR/build/bin/llama-cli"
echo ""
echo "Usage example:"
echo "  llama-cli -m ~/.ollama/models/blobs/<model.gguf> -p 'Hello' -ngl 999"
echo "  (-ngl 999 = すべてのlayerをGPUにオフロード)"
