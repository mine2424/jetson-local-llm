#!/bin/bash
# scripts/fix_ollama_gpu.sh
# Ollama Docker コンテナに Jetson GPU 必須環境変数を適用し、GPU 動作を検証する
#
# 問題: 以前のコンテナには GGML_CUDA_NO_VMM=1 / OLLAMA_NUM_GPU=999 が未設定のため
#        GPU が使われず CPU 推論(~7 t/s)になっていた
#
# 解決: コンテナを停止→削除→正しい env で再作成→GPU 動作確認
#
# 使い方:
#   bash scripts/fix_ollama_gpu.sh           # 確認付き
#   bash scripts/fix_ollama_gpu.sh --force   # 確認スキップ

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
info()  { echo -e "${YELLOW}[--]${NC} $*"; }
err()   { echo -e "${RED}[NG]${NC} $*"; }
head_(){ echo -e "${CYAN}── $* ──${NC}"; }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

CONTAINER_NAME="ollama"
MODEL_DIR="$HOME/.ollama/models"

# ─── 必須 GPU 環境変数 ────────────────────────────────────────────────────────
# これら全てが揃っていないと Jetson で GPU が使われない
REQUIRED_ENV_VARS=(
  "GGML_CUDA_NO_VMM=1"
  "OLLAMA_NUM_GPU=999"
  "OLLAMA_FLASH_ATTENTION=1"
  "NVIDIA_VISIBLE_DEVICES=all"
)

echo ""
echo "════════════════════════════════════════════════════"
echo "  🔧 Ollama GPU 修正スクリプト"
echo "  Jetson Orin Nano Super 向け GPU 環境変数を適用"
echo "════════════════════════════════════════════════════"
echo ""

# ─── [1] 現在の状態を診断 ─────────────────────────────────────────────────────
head_ "1/5 現在の状態診断"

# コンテナが存在するか
if ! sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  err "ollama コンテナが存在しません"
  echo "  → bash setup/08_setup_jetson_containers.sh を実行してください"
  exit 1
fi
ok "ollama コンテナ: 存在確認"

# 現在のenv確認
MISSING_VARS=()
CURRENT_ENV=$(sudo docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{.}} {{end}}' 2>/dev/null || true)
for var in "${REQUIRED_ENV_VARS[@]}"; do
  if echo "$CURRENT_ENV" | grep -q "$var"; then
    ok "  $var ✅"
  else
    err "  $var ❌ 未設定"
    MISSING_VARS+=("$var")
  fi
done

if [ ${#MISSING_VARS[@]} -eq 0 ]; then
  ok "全ての GPU 環境変数が設定済み"
  # GPU実際に使われているか確認（コンテナが起動中なら）
  if sudo docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    GPU_MEM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "?")
    info "現在のGPUメモリ使用量: ${GPU_MEM} MiB"
  fi
  if ! $FORCE; then
    echo ""
    read -r -p "環境変数は設定済みですが、再作成して確認しますか？ [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "スキップしました。"; exit 0; }
  fi
else
  echo ""
  echo -e "${RED}⚠️  ${#MISSING_VARS[@]} 個の必須 GPU 環境変数が未設定です。${NC}"
  echo "   → コンテナを再作成します"
fi

echo ""

# ─── [2] 使用イメージを確認 ───────────────────────────────────────────────────
head_ "2/5 使用イメージ確認"

CURRENT_IMAGE=$(sudo docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}' 2>/dev/null || true)
if [ -z "$CURRENT_IMAGE" ]; then
  # autotag で解決
  if command -v autotag &>/dev/null; then
    CURRENT_IMAGE=$(autotag ollama 2>/dev/null || true)
  fi
fi

if [ -z "$CURRENT_IMAGE" ]; then
  err "イメージを特定できません"
  echo "  → bash setup/08_setup_jetson_containers.sh を実行してください"
  exit 1
fi
ok "イメージ: $CURRENT_IMAGE"

echo ""

# ─── [3] コンテナ停止・削除 ──────────────────────────────────────────────────
head_ "3/5 コンテナ停止・削除"

if ! $FORCE; then
  echo "  コンテナ '${CONTAINER_NAME}' を停止・削除して再作成します"
  read -r -p "  続行しますか？ [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "中断しました。"; exit 0; }
fi

# モデルのアンロード（Ollama APIが応答する場合）
if curl -s http://localhost:11434/api/ps > /dev/null 2>&1; then
  info "ロード中のモデルをアンロード中..."
  curl -s http://localhost:11434/api/ps | python3 -c "
import sys, json
try:
    for m in json.load(sys.stdin).get('models', []):
        print(m['name'])
except: pass
" 2>/dev/null | while read -r m; do
    curl -s -X POST http://localhost:11434/api/generate \
      -d "{\"model\": \"$m\", \"keep_alive\": 0}" > /dev/null 2>&1 || true
  done
fi

sudo docker stop "$CONTAINER_NAME" 2>/dev/null || true
sleep 1

# MAXN + jetson_clocks + drop_caches
info "パフォーマンス最適化を適用中..."
MAXN_ID=$(grep -i "POWER_MODEL" /etc/nvpmodel.conf 2>/dev/null | grep -i "MAXN" | grep -o "ID=[0-9]*" | head -1 | cut -d= -f2 || echo "0")
sudo nvpmodel -m "${MAXN_ID:-0}" 2>/dev/null && ok "nvpmodel MAXN (ID=${MAXN_ID:-0})" || true
sudo jetson_clocks 2>/dev/null && ok "jetson_clocks" || true
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' && ok "drop_caches"

FREE_MB=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')
info "空きメモリ: ${FREE_MB} MB"

sudo docker rm "$CONTAINER_NAME" 2>/dev/null || true
ok "コンテナ削除完了"

echo ""

# ─── [4] GPU 環境変数付きで再作成 ────────────────────────────────────────────
head_ "4/5 コンテナ再作成 (GPU 環境変数あり)"

mkdir -p "$MODEL_DIR"

info "起動中: $CURRENT_IMAGE"
info "適用する GPU 環境変数:"
echo "    GGML_CUDA_NO_VMM=1       ← Jetson 統合メモリ必須"
echo "    OLLAMA_NUM_GPU=999       ← 全レイヤー GPU オフロード"
echo "    OLLAMA_FLASH_ATTENTION=1 ← Flash Attention"
echo ""

sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e GGML_CUDA_NO_VMM=1 \
  -e OLLAMA_NUM_GPU=999 \
  -e GGML_CUDA_FORCE_MMQ=1 \
  -e OLLAMA_FLASH_ATTENTION=1 \
  -e OLLAMA_MAX_LOADED_MODELS=1 \
  -e OLLAMA_KEEP_ALIVE=5m \
  -e OLLAMA_NUM_CTX=2048 \
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v "$MODEL_DIR:/data/models/ollama/models" \
  -p 127.0.0.1:11434:11434 \
  --restart unless-stopped \
  "$CURRENT_IMAGE" \
  /bin/sh -c '/start_ollama; tail -f /data/logs/ollama.log'

# API 起動待ち
info "API 応答待ち..."
for i in $(seq 1 20); do
  if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    ok "Ollama API 起動完了 (http://localhost:11434)"
    break
  fi
  [ "$i" -eq 20 ] && { err "API が応答しません: sudo docker logs ollama"; exit 1; }
  sleep 2
done

echo ""

# ─── [5] GPU 動作検証 ──────────────────────────────────────────────────────────
head_ "5/5 GPU 動作検証"

# 利用可能なモデルを確認
MODELS=$(curl -s http://localhost:11434/api/tags 2>/dev/null | \
  python3 -c "
import sys, json
try:
    models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
    print('\n'.join(models))
except: pass
" 2>/dev/null || true)

if [ -z "$MODELS" ]; then
  info "テスト推論用のモデルがありません"
  info "以下で pull してから GPU 確認できます:"
  echo "    curl -X POST http://localhost:11434/api/pull \\"
  echo "      -d '{\"name\": \"qwen3.5:4b-q4_K_M\"}'"
  echo ""
  ok "コンテナ再作成完了 (GPU env 設定済み)"
else
  TEST_MODEL=$(echo "$MODELS" | head -1)
  info "テスト推論を実行中: $TEST_MODEL"
  info "(GPU が使われていれば nvidia-smi でメモリ使用量が増加します)"
  echo ""

  # GPU メモリ: 推論前
  GPU_BEFORE=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "?")
  info "GPU メモリ (推論前): ${GPU_BEFORE} MiB"

  # テスト推論 (stream=false で同期)
  RESPONSE=$(curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$TEST_MODEL\", \"prompt\": \"1+1=\", \"stream\": false}" \
    --max-time 60 2>/dev/null | \
    python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    resp = d.get('response', '')
    dur = d.get('eval_duration', 0)
    ntok = d.get('eval_count', 0)
    tps = ntok / (dur / 1e9) if dur > 0 else 0
    print(f'応答: {resp.strip()[:50]}')
    print(f'速度: {tps:.1f} t/s ({ntok} tokens)')
except Exception as e:
    print(f'パースエラー: {e}')
" 2>/dev/null || echo "推論失敗")

  # GPU メモリ: 推論後
  GPU_AFTER=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "?")

  echo ""
  echo "$RESPONSE"
  echo ""
  info "GPU メモリ (推論後): ${GPU_AFTER} MiB"

  if [ "$GPU_BEFORE" != "?" ] && [ "$GPU_AFTER" != "?" ]; then
    GPU_DIFF=$((GPU_AFTER - GPU_BEFORE))
    if [ "$GPU_DIFF" -gt 100 ]; then
      ok "✅ GPU 確認: ${GPU_DIFF} MiB のメモリが割り当てられました → GPU 動作中"
    else
      err "⚠️  GPU メモリ変化が少ない (${GPU_DIFF} MiB) → CPU で推論されている可能性"
      echo ""
      echo "  確認コマンド:"
      echo "    sudo docker exec ollama env | grep CUDA"
      echo "    sudo docker logs ollama 2>&1 | grep -i 'cuda\|gpu'"
    fi
  fi
fi

echo ""
echo "════════════════════════════════════════════════════"
ok "完了"
echo ""
echo "  コンテナの GPU env 確認:"
echo "    sudo docker inspect ollama | grep -A2 GGML_CUDA"
echo ""
echo "  Ollama ログ確認:"
echo "    sudo docker logs -f ollama"
echo "════════════════════════════════════════════════════"
