#!/bin/bash
# install.sh - Jetson Local LLM セットアップ (ワンショット)
#
# 使い方:
#   bash install.sh
#
# 実行内容:
#   1. 環境チェック (JetPack / Docker / CUDA)
#   2. Docker nvidia runtime 設定
#   3. jetson-containers インストール (autotag コマンド)
#   4. NvMap メモリ最適化 (vm.min_free_kbytes)
#   5. autotag でイメージ解決 → Ollama コンテナ起動
#   6. スターターモデル pull (Ollama API 経由)
#   7. Open WebUI 起動 (オプション)

set -e

# ─── 定数 ────────────────────────────────────────────────────────────────────
STARTER_MODEL="qwen2.5:3b"
WEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
JC_DIR="$HOME/jetson-containers"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

# ─── 1. 環境チェック ──────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  Jetson Local LLM セットアップ"
echo "══════════════════════════════════════════════"
echo ""

info "環境を確認しています..."

# JetPack
if [ -f /etc/nv_tegra_release ]; then
  L4T=$(head -1 /etc/nv_tegra_release)
  ok "JetPack: $L4T"
else
  err "JetPack が検出できません (/etc/nv_tegra_release なし)"
  exit 1
fi

# Docker
if ! command -v docker &>/dev/null; then
  err "Docker が見つかりません。インストールしてください:"
  echo "    curl -fsSL https://get.docker.com | sh"
  echo "    sudo usermod -aG docker \$USER && newgrp docker"
  exit 1
fi
ok "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

# git (jetson-containers に必要)
if ! command -v git &>/dev/null; then
  err "git が見つかりません: sudo apt install git"
  exit 1
fi
ok "git: $(git --version)"

# メモリ
MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
MEM_FREE=$(awk '/MemFree/  {print int($2/1024)}' /proc/meminfo)
ok "メモリ: 合計 ${MEM_TOTAL}MB / 空き ${MEM_FREE}MB"

# ストレージ
DISK_FREE=$(df -h / | tail -1 | awk '{print $4}')
ok "ストレージ空き: ${DISK_FREE}"

echo ""

# ─── 2. Docker daemon - nvidia runtime 設定 ──────────────────────────────────
echo "── [1/6] Docker nvidia runtime ──"

# nvidia-container-runtime
if ! command -v nvidia-container-runtime &>/dev/null; then
  info "nvidia-container-runtime をインストール中..."
  sudo apt-get install -y nvidia-container 2>/dev/null || \
  sudo apt-get install -y nvidia-container-runtime
fi
ok "nvidia-container-runtime: $(nvidia-container-runtime --version 2>/dev/null | head -1 || echo 'installed')"

# daemon.json に nvidia runtime を設定
DAEMON_JSON="/etc/docker/daemon.json"
if ! sudo cat "$DAEMON_JSON" 2>/dev/null | grep -q '"nvidia"'; then
  info "daemon.json に nvidia runtime を追加中..."
  sudo tee "$DAEMON_JSON" > /dev/null <<'EOF'
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
  ok "daemon.json を更新しました"
else
  ok "daemon.json: nvidia runtime 設定済み"
fi

# Docker 起動・再起動
sudo systemctl enable --now docker > /dev/null 2>&1
sudo systemctl restart docker
sleep 2
ok "Docker daemon 起動済み"

# docker グループにユーザーを追加
if ! groups "$USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  ok "docker グループに $USER を追加しました (再ログイン後に sudo 不要)"
else
  ok "docker グループ: 設定済み"
fi

echo ""

# ─── 3. jetson-containers インストール ────────────────────────────────────────
echo "── [2/6] jetson-containers (autotag) ──"

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
  export PATH="$HOME/.local/bin:$PATH"
  ok "autotag: インストール完了"
else
  ok "autotag: インストール済み"
fi

echo ""

# ─── 4. NvMap メモリ最適化 ───────────────────────────────────────────────────
echo "── [3/6] NvMap メモリ最適化 ──"

sudo tee /etc/sysctl.d/99-ollama-jetson.conf > /dev/null <<'EOF'
# Jetson NvMap 用に MemFree を常時 2GB 確保する
# NvMap はページキャッシュを再利用できず MemFree からのみ割り当てるため
vm.min_free_kbytes = 2097152
EOF
sudo sysctl -p /etc/sysctl.d/99-ollama-jetson.conf > /dev/null
ok "vm.min_free_kbytes = 2097152 適用"

# native Ollama が動いていたら止める (ポート競合防止)
if systemctl is-active --quiet ollama 2>/dev/null; then
  info "ネイティブ Ollama を停止・無効化..."
  sudo systemctl stop ollama
  sudo systemctl disable ollama
  ok "ネイティブ Ollama 無効化"
fi

# ページキャッシュ解放
info "ページキャッシュを解放中..."
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
MEM_FREE=$(awk '/MemFree/ {print int($2/1024)}' /proc/meminfo)
ok "MemFree = ${MEM_FREE}MB"

echo ""

# ─── 5. autotag でイメージ解決 → Ollama コンテナ起動 ─────────────────────────
echo "── [4/6] Ollama コンテナ (autotag) ──"

IMAGE=$(autotag ollama 2>/dev/null || true)
if [ -z "$IMAGE" ]; then
  err "autotag が ollama イメージを解決できませんでした"
  err "JetPack バージョンを確認してください: cat /etc/nv_tegra_release"
  exit 1
fi
ok "使用イメージ: $IMAGE"

# 既存コンテナの処理
if sudo docker ps -a --format '{{.Names}}' | grep -q "^ollama$"; then
  info "既存の ollama コンテナを削除して作り直します..."
  sudo docker stop ollama 2>/dev/null || true
  sudo docker rm ollama 2>/dev/null || true
fi

mkdir -p "$HOME/.ollama/models"

info "コンテナを起動中: $IMAGE"
sudo docker run -d \
  --name ollama \
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

# API が応答するまで待機
info "API 応答待ち..."
for i in $(seq 1 15); do
  if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    ok "Ollama API 起動完了 (http://localhost:11434)"
    break
  fi
  [ "$i" -eq 15 ] && { err "API が応答しません: sudo docker logs ollama を確認してください"; exit 1; }
  sleep 2
done

echo ""

# ─── 6. スターターモデル pull (API経由) ──────────────────────────────────────
echo "── [5/6] スターターモデル ──"

info "モデルをダウンロード中: $STARTER_MODEL (~2GB)"
echo "  (Ollama API 経由)"

pull_result=$(curl -s -X POST http://localhost:11434/api/pull \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$STARTER_MODEL\"}" \
  2>&1 | python3 -c "
import sys, json
last = ''
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        s = d.get('status', '')
        if 'total' in d and d['total'] > 0:
            pct = int(d.get('completed', 0) / d['total'] * 100)
            print(f'\r  {s}: {pct}%', end='', flush=True)
        elif s:
            print(f'  {s}')
        last = d.get('status', last)
    except:
        pass
print()
print(last)
" 2>&1 | tail -1 || echo "error")

if [ "$pull_result" = "success" ]; then
  ok "$STARTER_MODEL ダウンロード完了"
else
  err "モデルのダウンロードに失敗しました (あとで pull できます)"
  err "  curl -X POST http://localhost:11434/api/pull -d '{\"name\":\"$STARTER_MODEL\"}'"
fi

echo ""

# ─── 7. Open WebUI (オプション) ──────────────────────────────────────────────
echo "── [6/6] Open WebUI ──"

read -r -p "Open WebUI (ブラウザ管理画面) もセットアップしますか？ [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  if sudo docker ps -a --format '{{.Names}}' | grep -q "^open-webui$"; then
    info "既存の open-webui コンテナを起動します..."
    sudo docker start open-webui > /dev/null 2>&1
  else
    info "Open WebUI コンテナを起動中: $WEBUI_IMAGE"
    sudo docker run -d \
      --name open-webui \
      --network host \
      --restart always \
      -v open-webui:/app/backend/data \
      -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
      "$WEBUI_IMAGE"
  fi
  IP=$(hostname -I | awk '{print $1}')
  ok "Open WebUI 起動済み → http://localhost:8080  /  http://${IP}:8080"
else
  info "Open WebUI はスキップしました"
fi

echo ""

# ─── 完了メッセージ ───────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo -e "  ${GREEN}セットアップ完了！${NC}"
echo "══════════════════════════════════════════════"
echo ""
echo "  コンテナ状態:"
sudo docker ps --format "    {{.Names}}\t{{.Status}}\t{{.Image}}" \
  --filter "name=ollama" --filter "name=open-webui"
echo ""
echo "  すぐ試す (API経由):"
echo "    curl http://localhost:11434/api/tags"
echo "    curl -X POST http://localhost:11434/api/generate \\"
echo "      -d '{\"model\": \"$STARTER_MODEL\", \"prompt\": \"こんにちは\", \"stream\": false}'"
echo ""
echo "  管理コマンド:"
echo "    sudo docker logs -f ollama    # ログ確認"
echo "    sudo docker stop ollama       # 停止"
echo "    sudo docker start ollama      # 起動"
echo ""
echo "  TUI メニュー:"
echo "    bash menu.sh"
echo ""
