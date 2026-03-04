#!/bin/bash
# setup/08_setup_jetson_containers.sh - jetson-containers 経由の Ollama セットアップ
#
# 参考: https://zenn.dev/karaage0703/articles/3a2067b6b92e06
#
# 既存の 05_setup_docker_ollama.sh との違い:
#   - イメージタグを autotag コマンドで動的解決 (JetPack バージョン非依存)
#   - jetson-containers CLI のインストールを自動化
#   - Ollama CLI は一切使用せず、HTTP API のみ

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

CONTAINER_NAME="ollama"
JC_DIR="$HOME/jetson-containers"

# ─── sudo チェック ────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  info "sudo 権限が必要です。パスワードを入力してください。"
  sudo -v || { err "sudo 権限を取得できませんでした"; exit 1; }
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo "  🧩 jetson-containers Ollama セットアップ"
echo "  (autotag で JetPack に合ったイメージを自動解決)"
echo "══════════════════════════════════════════════════════"
echo ""

# ─── [1/6] 前提条件チェック ───────────────────────────────────────────────────
echo "── [1/6] 前提条件チェック ──"

# git
if ! command -v git &>/dev/null; then
  err "git が見つかりません: sudo apt install git"
  exit 1
fi
ok "git: $(git --version)"

# Docker デーモン
if ! systemctl is-active docker &>/dev/null; then
  info "Docker を有効化・起動中..."
  sudo systemctl enable --now docker
fi
ok "Docker: 起動済み"

# nvidia-container-runtime
if ! command -v nvidia-container-runtime &>/dev/null; then
  info "nvidia-container-runtime をインストール中..."
  sudo apt-get install -y nvidia-container
  ok "nvidia-container-runtime: インストール完了"
else
  ok "nvidia-container-runtime: インストール済み"
fi

# daemon.json に nvidia runtime が設定されているか確認・追加
if ! sudo cat /etc/docker/daemon.json 2>/dev/null | grep -q "nvidia"; then
  info "/etc/docker/daemon.json に nvidia runtime を設定中..."
  sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
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
  sudo systemctl restart docker
  sleep 2
  ok "daemon.json: nvidia runtime を設定・再起動完了"
else
  ok "daemon.json: nvidia runtime 設定済み"
fi

# ─── [2/6] jetson-containers インストール ─────────────────────────────────────
echo ""
echo "── [2/6] jetson-containers インストール ──"

if [ ! -d "$JC_DIR" ]; then
  info "jetson-containers をクローン中..."
  git clone --depth=1 https://github.com/dusty-nv/jetson-containers "$JC_DIR"
  ok "クローン完了: $JC_DIR"
else
  ok "jetson-containers は既にクローン済み: $JC_DIR"
fi

if ! command -v autotag &>/dev/null; then
  info "jetson-containers install.sh を実行中..."
  bash "$JC_DIR/install.sh"
  # このセッションで使えるように PATH を更新
  export PATH="$HOME/.local/bin:$PATH"
  ok "autotag: インストール完了"
else
  ok "autotag: インストール済み ($(which autotag))"
fi

# install.sh 実行後も autotag が見つからない場合はフォールバック
if ! command -v autotag &>/dev/null; then
  err "autotag コマンドが見つかりません"
  err "手動で確認してください: ls ~/.local/bin/"
  err "または: source ~/.bashrc && autotag ollama"
  exit 1
fi

# ─── [3/6] autotag でイメージ解決 ─────────────────────────────────────────────
echo ""
echo "── [3/6] autotag ollama でイメージ名を解決中 ──"

IMAGE=$(autotag ollama 2>/dev/null || true)
if [ -z "$IMAGE" ]; then
  err "autotag が ollama イメージを解決できませんでした"
  err "JetPack バージョンを確認してください: cat /etc/nv_tegra_release"
  exit 1
fi
ok "使用イメージ: $IMAGE"

# ─── [4/6] sysctl チューニング + ページキャッシュ解放 ────────────────────────
echo ""
echo "── [4/6] sysctl チューニング (vm.min_free_kbytes = 2097152) ──"

# NvMap は MemFree からのみ割り当て可能なため 2GB 確保
sudo tee /etc/sysctl.d/99-ollama-jetson.conf > /dev/null <<'EOF'
# Jetson NvMap 用に MemFree を 2GB 以上確保する
# NvMap はページキャッシュを再利用できず MemFree からのみ割り当てるため。
vm.min_free_kbytes = 2097152
EOF
sudo sysctl -p /etc/sysctl.d/99-ollama-jetson.conf
ok "vm.min_free_kbytes = 2097152 適用済み"

info "ページキャッシュを解放中 (NvMap 用 MemFree を確保)..."
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
local_free_mb=$(awk '/MemFree/ {print int($2/1024)}' /proc/meminfo)
ok "ページキャッシュ解放完了: MemFree = ${local_free_mb}MB"

# ─── [5/6] 既存コンテナの停止・削除 ──────────────────────────────────────────
echo ""
echo "── [5/6] 既存コンテナの確認・停止 ──"

if sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  info "既存コンテナ '${CONTAINER_NAME}' を停止・削除します..."
  sudo docker stop "$CONTAINER_NAME" 2>/dev/null || true
  sudo docker rm   "$CONTAINER_NAME" 2>/dev/null || true
  ok "既存コンテナを削除しました"
else
  ok "既存コンテナなし (新規作成します)"
fi

# ─── [6/6] Ollama コンテナ起動 ────────────────────────────────────────────────
echo ""
echo "── [6/6] Ollama コンテナを起動中 ──"
echo "     イメージ: $IMAGE"

mkdir -p "$HOME/.ollama/models"

# dustynv/ollama は OLLAMA_MODELS=/data/models/ollama/models を使う
# /start_ollama はサーバをバックグラウンド起動して終了するため、
# tail -f でコンテナを生存させる
sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e GGML_CUDA_NO_VMM=1 \
  -e OLLAMA_NUM_GPU=999 \
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

ok "コンテナ起動コマンド送信完了"

# ─── API 応答待機 (最大 30 秒) ────────────────────────────────────────────────
echo ""
echo "── API 応答確認中 (最大30秒) ──"

for i in $(seq 1 10); do
  if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo ""
    echo "══════════════════════════════════════════════════════"
    ok "jetson-containers Ollama セットアップ完了"
    echo "══════════════════════════════════════════════════════"
    echo ""
    echo "  Ollama API: http://localhost:11434"
    echo ""
    echo "  コンテナ状態:"
    sudo docker ps --filter "name=^${CONTAINER_NAME}$" --format "  {{.Names}}\t{{.Status}}\t{{.Image}}"
    echo ""
    echo "  使用イメージ: $IMAGE"
    echo "  (autotag による JetPack 自動解決)"
    echo ""
    echo "  モデルのダウンロード (API 経由):"
    echo "    curl -X POST http://localhost:11434/api/pull \\"
    echo "      -d '{\"name\":\"qwen2.5:3b\"}'"
    echo ""
    exit 0
  fi
  info "待機中... (${i}/10)"
  sleep 3
done

echo ""
err "API が30秒以内に応答しませんでした"
err "ログを確認してください:"
err "  sudo docker logs ${CONTAINER_NAME}"
exit 1
