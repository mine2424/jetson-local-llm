#!/bin/bash
# setup/05_setup_docker_ollama.sh
# Docker ベースの Ollama セットアップ (Jetson R36.x 向け)
#
# 背景:
#   native Ollama は NvMap が MemFree (~1.3GB) しか使えないため CUDA OOM になる。
#   dustynv/ollama コンテナはJetson (L4T R36.x) 向けにビルドされており、
#   正しいCUDAライブラリをバンドルしている。
#   コンテナも同じNvMapパスを通るため、drop_caches + vm.min_free_kbytes の
#   チューニングが必要。

set -e

IMAGE="dustynv/ollama:r36.4.0"
CONTAINER_NAME="ollama"

echo "=== Docker Ollama セットアップ (Jetson L4T R36.4.x) ==="
echo ""

# --- 1. Docker デーモン起動 ---
echo "[1/8] Docker デーモンを有効化・起動中..."
sudo systemctl enable --now docker
echo "     OK: Docker 起動済み"

# --- 2. nvidia-container ランタイムのインストール ---
echo "[2/8] nvidia-container-runtime の確認..."
if ! command -v nvidia-container-runtime &>/dev/null; then
  echo "     インストール中: nvidia-container ..."
  sudo apt-get install -y nvidia-container
  echo "     OK: nvidia-container-runtime インストール完了"
else
  echo "     OK: nvidia-container-runtime は既にインストール済み"
fi

# daemon.json に nvidia runtime が設定されているか確認
if ! sudo cat /etc/docker/daemon.json 2>/dev/null | grep -q "nvidia"; then
  echo "     [警告] /etc/docker/daemon.json に nvidia runtime が設定されていません"
  echo "     以下を /etc/docker/daemon.json に追加してください:"
  cat <<'EOF'
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "default-runtime": "nvidia"
}
EOF
  echo "     設定後: sudo systemctl restart docker"
else
  echo "     OK: daemon.json に nvidia runtime 設定あり"
fi

# Docker を再起動して設定を反映
sudo systemctl restart docker
sleep 2

# --- 3. nvidia-smi スモークテスト (任意) ---
echo "[3/8] NVIDIA ランタイム検証中..."
if docker run --rm --runtime nvidia dustynv/l4t-base:r36.4.0 nvidia-smi &>/dev/null; then
  echo "     OK: nvidia-smi が GPU を検出しました"
else
  echo "     [警告] スモークテスト失敗。GPU アクセスを確認してください"
  echo "     (セットアップは続行します)"
fi

# --- 4. ネイティブ Ollama サービスを無効化 ---
echo "[4/8] ネイティブ Ollama サービスを停止・無効化..."
sudo systemctl stop ollama 2>/dev/null || true
sudo systemctl disable ollama 2>/dev/null || true
echo "     OK: ネイティブ Ollama 無効化完了"

# --- 5. sysctl チューニング (NvMap 用に 2GB 確保) ---
echo "[5/8] sysctl チューニング (vm.min_free_kbytes = 2097152)..."
sudo tee /etc/sysctl.d/99-ollama-jetson.conf > /dev/null <<'EOF'
# Jetson NvMap 用に MemFree を 2GB 以上確保する
# NvMap はページキャッシュを再利用できず MemFree からのみ割り当てるため。
vm.min_free_kbytes = 2097152
EOF
sudo sysctl -p /etc/sysctl.d/99-ollama-jetson.conf
echo "     OK: vm.min_free_kbytes = 2097152 適用済み"

# --- 6. ページキャッシュ解放 ---
echo "[6/8] ページキャッシュを解放中 (NvMap 用 MemFree を確保)..."
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
local_free_mb=$(awk '/MemFree/ {print int($2/1024)}' /proc/meminfo)
echo "     OK: MemFree = ${local_free_mb}MB"

# --- 7. Ollama コンテナ作成・起動 ---
echo "[7/8] Ollama コンテナを作成・起動中..."
echo "     イメージ: $IMAGE"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "     既存コンテナ '${CONTAINER_NAME}' を起動します..."
  docker start "$CONTAINER_NAME"
else
  echo "     新規コンテナを作成します..."
  # dustynv/ollama は OLLAMA_MODELS=/data/models/ollama/models を使う
  # /start_ollama はサーバをバックグラウンド起動して終了するため、
  # tail -f でコンテナを生存させる
  mkdir -p "$HOME/.ollama/models"
  docker run -d \
    --name "$CONTAINER_NAME" \
    --runtime nvidia \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e OLLAMA_FLASH_ATTENTION=1 \
    -e OLLAMA_MAX_LOADED_MODELS=1 \
    -e OLLAMA_KEEP_ALIVE=5m \
    -e OLLAMA_NUM_CTX=2048 \
    -e OLLAMA_HOST=0.0.0.0:11434 \
    -v "$HOME/.ollama/models:/data/models/ollama/models" \
    -p 127.0.0.1:11434:11434 \
    --restart unless-stopped \
    "$IMAGE" \
    /bin/sh -c '/start_ollama; tail -f /data/logs/ollama.log'
fi
echo "     OK: コンテナ起動済み"

# --- 8. API 応答確認 ---
echo "[8/8] API 応答を確認中 (最大30秒)..."
for i in $(seq 1 10); do
  if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo ""
    echo "=== セットアップ完了 ==="
    echo ""
    echo "Ollama API: http://localhost:11434"
    echo "コンテナ状態:"
    docker ps --filter "name=^${CONTAINER_NAME}$" --format "  {{.Names}}\t{{.Status}}"
    echo ""
    echo "次のステップ:"
    echo "  ollama pull qwen2.5:3b    # 軽量モデルをダウンロード"
    echo "  ollama run qwen2.5:3b \"hello\""
    echo "  docker exec ${CONTAINER_NAME} ollama ps   # VRAM使用状況を確認"
    echo ""
    exit 0
  fi
  echo "     待機中... (${i}/10)"
  sleep 3
done

echo ""
echo "[エラー] API が応答しません。ログを確認してください:"
echo "  docker logs ${CONTAINER_NAME}"
exit 1
