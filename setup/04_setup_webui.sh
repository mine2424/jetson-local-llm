#!/bin/bash
# Open WebUI セットアップ (Ollamaのブラウザ管理UI)
# Ollamaが起動済みであること前提
set -e

echo "=== Setting up Open WebUI for Jetson ==="

# Dockerが必要
if ! command -v docker &>/dev/null; then
  echo "❌ Docker not found. Install Docker first:"
  echo "   curl -fsSL https://get.docker.com | sh"
  echo "   sudo usermod -aG docker \$USER"
  exit 1
fi

# Open WebUI コンテナ起動
# --network=host でローカルのOllamaに接続
sudo docker run -d \
  --name open-webui \
  --network=host \
  --restart=always \
  -v open-webui:/app/backend/data \
  -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
  ghcr.io/open-webui/open-webui:main

echo ""
echo "✅ Open WebUI started"
echo "   → http://localhost:8080"
echo "   (同一LAN内: http://$(hostname -I | awk '{print $1}'):8080)"
echo ""
echo "管理コマンド:"
echo "  docker ps                          # 稼働確認"
echo "  docker logs open-webui -f          # ログ"
echo "  docker stop open-webui             # 停止"
echo "  docker start open-webui            # 再起動"
