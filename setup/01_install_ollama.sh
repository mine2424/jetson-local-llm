#!/bin/bash
# Ollama インストール (Jetson / ARM64対応)
set -e

echo "=== Installing Ollama for Jetson (ARM64) ==="

# 既存インストール確認
if command -v ollama &>/dev/null; then
  echo "Ollama already installed: $(ollama --version)"
  echo "Update? (y/N)"
  read -r answer
  [[ "$answer" != "y" ]] && exit 0
fi

# ARM64用バイナリを直接インストール
curl -fsSL https://ollama.com/install.sh | sh

# インストール確認
echo ""
echo "[Verification]"
ollama --version

# Jetson向け環境変数設定
OLLAMA_ENV_FILE="/etc/systemd/system/ollama.service.d/jetson.conf"
sudo mkdir -p "$(dirname $OLLAMA_ENV_FILE)"
sudo tee "$OLLAMA_ENV_FILE" > /dev/null <<'EOF'
[Service]
# Jetson共有メモリ最適化
Environment="OLLAMA_NUM_GPU=1"
# モデルストレージ先 (NVMe SSD)
Environment="OLLAMA_MODELS=/home/$USER/.ollama/models"
# APIホスト (外部からアクセスする場合は 0.0.0.0)
Environment="OLLAMA_HOST=127.0.0.1:11434"
# アイドル後にGPUメモリを解放 (Jetson統合メモリ節約)
Environment="OLLAMA_KEEP_ALIVE=5m"
# 同時ロードモデルを1つに制限 (7B=~4.5GBのため)
Environment="OLLAMA_MAX_LOADED_MODELS=1"
# Flash Attention でVRAM使用量を30-40%削減
Environment="OLLAMA_FLASH_ATTENTION=1"
# デフォルト32768→2048に制限 (KVキャッシュ3.7GB→234MB削減)
Environment="OLLAMA_NUM_CTX=2048"
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl start ollama

echo ""
echo "✅ Ollama installed and started"
echo "   API: http://localhost:11434"
echo "   Models dir: ~/.ollama/models"
echo ""
echo "Next: bash setup/03_pull_models.sh"
