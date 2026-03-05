#!/bin/bash
# scripts/fix_ollama_gpu.sh
# Ollama Docker コンテナの GPU 動作を診断・修正する
#
# 問題: GGML_CUDA_NO_VMM=1 等が設定済みでも GPU が使われないケースがある
#       原因: (a) コンテナ内 nvidia-smi が使えない (Docker runtime 設定ミス)
#             (b) Ollama バイナリが古く CUDA 対応が不十分
#             (c) drop_caches 不足でメモリ不足に陥る
#
# 解決フロー:
#   1. コンテナ内 nvidia-smi で GPU アクセス確認
#   2. Ollama ログで CUDA 初期化確認
#   3. GPU env 未設定なら再作成
#   4. Ollama バイナリを最新にアップグレード (dustynv/ollama が古い場合)
#   5. 実推論で GPU メモリ増加を確認
#
# 使い方:
#   bash scripts/fix_ollama_gpu.sh           # 対話式
#   bash scripts/fix_ollama_gpu.sh --force   # 確認スキップ
#   bash scripts/fix_ollama_gpu.sh --diag    # 診断のみ (変更なし)
#   bash scripts/fix_ollama_gpu.sh --upgrade # コンテナ再作成 + Ollama バイナリ upgrade

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
info()  { echo -e "${YELLOW}[--]${NC} $*"; }
err()   { echo -e "${RED}[NG]${NC} $*"; }
head_(){ echo -e "\n${CYAN}${BOLD}── $* ──${NC}"; }

FORCE=false
DIAG_ONLY=false
UPGRADE=false
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=true ;;
    --diag)    DIAG_ONLY=true ;;
    --upgrade) UPGRADE=true; FORCE=true ;;
  esac
done

CONTAINER_NAME="ollama"
MODEL_DIR="$HOME/.ollama/models"

# ─── 必須 GPU 環境変数 ────────────────────────────────────────────────────────
REQUIRED_ENV_VARS=(
  "GGML_CUDA_NO_VMM=1"
  "OLLAMA_NUM_GPU=999"
  "OLLAMA_FLASH_ATTENTION=1"
  "NVIDIA_VISIBLE_DEVICES=all"
)

echo ""
echo "════════════════════════════════════════════════════"
echo "  🔧 Ollama GPU 診断・修正スクリプト"
echo "  Jetson Orin Nano Super 向け"
echo "════════════════════════════════════════════════════"
echo ""

# ─── [1] コンテナ存在確認 ─────────────────────────────────────────────────────
head_ "1/6 コンテナ確認"

if ! sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  err "ollama コンテナが存在しません"
  echo "  → bash setup/08_setup_jetson_containers.sh を実行してください"
  exit 1
fi
ok "ollama コンテナ: 存在確認"

CONTAINER_RUNNING=false
sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$" && CONTAINER_RUNNING=true

# ─── [2] コンテナ内 GPU アクセス診断 ─────────────────────────────────────────
head_ "2/6 コンテナ内 GPU アクセス診断"

# まずコンテナを起動しておく (診断のため)
if ! $CONTAINER_RUNNING; then
  info "コンテナを一時起動 (診断のみ)..."
  sudo docker start "$CONTAINER_NAME" > /dev/null 2>&1 || true
  sleep 3
fi

# a) コンテナ内で nvidia-smi が使えるか
echo ""
echo -e "  ${BOLD}[2a] コンテナ内 nvidia-smi テスト${NC}"
if sudo docker exec "$CONTAINER_NAME" nvidia-smi > /dev/null 2>&1; then
  ok "nvidia-smi: コンテナ内で動作 ✅"
  GPU_DRIVER=$(sudo docker exec "$CONTAINER_NAME" nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "?")
  GPU_NAME=$(sudo docker exec "$CONTAINER_NAME" nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "?")
  echo "    GPU  : $GPU_NAME"
  echo "    Driver: $GPU_DRIVER"
  GPU_ACCESSIBLE=true
else
  err "nvidia-smi: コンテナ内で失敗 ❌"
  echo "    → Docker runtime に nvidia が設定されていない可能性"
  echo "    → コンテナを --runtime nvidia で再作成します"
  GPU_ACCESSIBLE=false
fi

# b) Ollama ログで CUDA 初期化を確認
echo ""
echo -e "  ${BOLD}[2b] Ollama ログ GPU 確認${NC}"
CUDA_IN_LOG=false
if sudo docker logs "$CONTAINER_NAME" 2>&1 | grep -qiE "cuda|ggml_cuda|gpu layer|loaded \d+ GPU"; then
  ok "Ollama ログ: CUDA/GPU 初期化あり ✅"
  sudo docker logs "$CONTAINER_NAME" 2>&1 | grep -iE "cuda|gpu layer|llm_load" | tail -5 | sed 's/^/    /'
  CUDA_IN_LOG=true
else
  err "Ollama ログ: CUDA/GPU 初期化なし ❌ (CPU モードで動作中)"
  echo "    最新ログ (末尾10行):"
  sudo docker logs --tail 10 "$CONTAINER_NAME" 2>&1 | sed 's/^/    /'
fi

# c) 現在の GPU env 確認
echo ""
echo -e "  ${BOLD}[2c] コンテナ GPU 環境変数${NC}"
CURRENT_ENV=$(sudo docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{.}} {{end}}' 2>/dev/null || true)
MISSING_VARS=()
for var in "${REQUIRED_ENV_VARS[@]}"; do
  if echo "$CURRENT_ENV" | grep -q "${var%=*}="; then
    ok "  $var ✅"
  else
    err "  $var ❌ 未設定"
    MISSING_VARS+=("$var")
  fi
done

# d) コンテナ内 Ollama バージョン確認
echo ""
echo -e "  ${BOLD}[2d] コンテナ内 Ollama バージョン${NC}"
OLLAMA_VER=$(sudo docker exec "$CONTAINER_NAME" ollama --version 2>/dev/null || echo "取得失敗")
info "Ollama バージョン: $OLLAMA_VER"

# ─── 診断レポート ─────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  📋 診断結果サマリー"
echo "════════════════════════════════════════"
$GPU_ACCESSIBLE  && echo -e "  GPU アクセス  : ${GREEN}OK${NC}" || echo -e "  GPU アクセス  : ${RED}NG → Docker runtime 修正が必要${NC}"
$CUDA_IN_LOG     && echo -e "  CUDA ログ     : ${GREEN}あり${NC}" || echo -e "  CUDA ログ     : ${RED}なし → GPU 未使用${NC}"
[ ${#MISSING_VARS[@]} -eq 0 ] \
  && echo -e "  GPU env vars  : ${GREEN}全て設定済み${NC}" \
  || echo -e "  GPU env vars  : ${RED}${#MISSING_VARS[@]}個未設定${NC}"
echo "════════════════════════════════════════"

# ─── 診断のみモード ───────────────────────────────────────────────────────────
if $DIAG_ONLY; then
  echo ""
  info "診断のみモード: 変更は行いません"
  echo ""
  echo "  GPU が使われていない場合の修正:"
  echo "    bash scripts/fix_ollama_gpu.sh --upgrade"
  echo ""
  exit 0
fi

# ─── 修正が必要かどうか判定 ───────────────────────────────────────────────────
NEED_FIX=false
if ! $GPU_ACCESSIBLE || [ ${#MISSING_VARS[@]} -gt 0 ]; then
  NEED_FIX=true
fi
# GPU アクセスOK・env OK でも CUDA ログがない場合 → バイナリ upgrade が必要
if $GPU_ACCESSIBLE && [ ${#MISSING_VARS[@]} -eq 0 ] && ! $CUDA_IN_LOG; then
  echo ""
  echo -e "${YELLOW}⚠️  GPU アクセスは OK ですが Ollama が CUDA を使っていません。${NC}"
  echo "   Ollama バイナリが古い可能性があります。"
  echo "   (dustynv/ollama イメージのバイナリは更新が遅いことがある)"
  UPGRADE=true
  FORCE=true
fi

if ! $NEED_FIX && ! $UPGRADE; then
  echo ""
  ok "修正不要です。GPU は正常に動作しています。"
  if ! $FORCE; then
    read -r -p "  それでも再作成しますか？ [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 0
    FORCE=true
  fi
fi

# ─── [3] パフォーマンス最適化 ─────────────────────────────────────────────────
head_ "3/6 パフォーマンス最適化 (MAXN + jetson_clocks + drop_caches)"

MAXN_ID=$(grep -i "POWER_MODEL" /etc/nvpmodel.conf 2>/dev/null | grep -i "MAXN" | grep -o "ID=[0-9]*" | head -1 | cut -d= -f2 || echo "0")
sudo nvpmodel -m "${MAXN_ID:-0}" 2>/dev/null && ok "nvpmodel MAXN (ID=${MAXN_ID:-0})" || true
sudo jetson_clocks 2>/dev/null && ok "jetson_clocks" || true
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' && ok "drop_caches"
FREE_MB=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')
info "空きメモリ: ${FREE_MB} MB"

# ─── [4] コンテナ停止・削除・再作成 ─────────────────────────────────────────
head_ "4/6 コンテナ再作成 (GPU env 確実に設定)"

if ! $FORCE; then
  echo "  GPU 環境変数を確実に設定してコンテナを再作成します。"
  read -r -p "  続行しますか？ [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "中断"; exit 0; }
fi

# イメージ確認
CURRENT_IMAGE=$(sudo docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}' 2>/dev/null || true)
if [ -z "$CURRENT_IMAGE" ] && command -v autotag &>/dev/null; then
  CURRENT_IMAGE=$(autotag ollama 2>/dev/null || true)
fi
[ -z "$CURRENT_IMAGE" ] && { err "イメージを特定できません。bash setup/08_setup_jetson_containers.sh を実行してください"; exit 1; }
ok "使用イメージ: $CURRENT_IMAGE"

# モデルのアンロード (API が応答する場合)
if curl -s http://localhost:11434/api/ps > /dev/null 2>&1; then
  info "ロード中のモデルをアンロード中..."
  curl -s http://localhost:11434/api/ps 2>/dev/null | python3 -c "
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
sudo docker rm "$CONTAINER_NAME" 2>/dev/null || true
ok "コンテナ削除完了"

mkdir -p "$MODEL_DIR"

info "GPU 環境変数付きでコンテナを再作成中..."
info "  GGML_CUDA_NO_VMM=1       ← Jetson 統合メモリ (必須)"
info "  OLLAMA_NUM_GPU=999       ← 全レイヤー GPU オフロード"
info "  OLLAMA_FLASH_ATTENTION=1 ← Flash Attention"
info "  GGML_CUDA_FORCE_MMQ=1    ← Q4_K_M 高速化"
info "  CUDA_VISIBLE_DEVICES=0   ← GPU 明示指定"
echo ""

sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e CUDA_VISIBLE_DEVICES=0 \
  -e GGML_CUDA_NO_VMM=1 \
  -e GGML_CUDA_FORCE_MMQ=1 \
  -e GGML_CUDA_NO_PEER_COPY=1 \
  -e OLLAMA_NUM_GPU=999 \
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
for i in $(seq 1 25); do
  if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    ok "Ollama API 起動完了"
    break
  fi
  [ "$i" -eq 25 ] && { err "API が応答しません: sudo docker logs ollama"; exit 1; }
  sleep 2
done

# ─── [5] Ollama バイナリ アップグレード ───────────────────────────────────────
if $UPGRADE; then
  head_ "5/6 Ollama バイナリ アップグレード (GPU 対応強化)"
  echo ""
  echo "  dustynv/ollama のバイナリは古い場合があり GPU を正しく認識しないことがある。"
  echo "  コンテナ内の Ollama を Jetson 向け最新バイナリに差し替えます。"
  echo ""

  # 戦略: dustynv/ollama は /start_ollama スクリプトで Ollama を起動している
  # コンテナ内で Ollama 公式インストールスクリプトを使うと上書きできる
  # ただし Jetson では ARM64 + CUDA が必要なので dustynv ビルドが安全

  # まず現在のバイナリパスを確認
  OLLAMA_BIN_PATH=$(sudo docker exec "$CONTAINER_NAME" which ollama 2>/dev/null || echo "/usr/local/bin/ollama")
  OLLAMA_VER_BEFORE=$(sudo docker exec "$CONTAINER_NAME" ollama --version 2>/dev/null || echo "不明")
  info "現在のバイナリ: $OLLAMA_BIN_PATH (version: $OLLAMA_VER_BEFORE)"

  # GitHub releases から最新 ARM64 Linux バイナリを取得して試みる
  # 注意: Jetson 向け CUDA サポートは dustynv ビルドにしかない場合がある
  #       → まず公式 ARM64 を試し、GPU 動作しない場合は dustynv に留まる
  LATEST_URL="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-arm64"
  info "最新 Ollama ARM64 バイナリを取得中..."
  if sudo docker exec "$CONTAINER_NAME" sh -c \
    "curl -fsSL $LATEST_URL -o /tmp/ollama-new && chmod +x /tmp/ollama-new && /tmp/ollama-new --version" 2>/dev/null; then
    OLLAMA_VER_NEW=$(sudo docker exec "$CONTAINER_NAME" /tmp/ollama-new --version 2>/dev/null || echo "?")
    ok "新バイナリ動作確認: $OLLAMA_VER_NEW"
    # バックアップ → 差し替え
    sudo docker exec "$CONTAINER_NAME" sh -c "cp $OLLAMA_BIN_PATH ${OLLAMA_BIN_PATH}.bak 2>/dev/null; cp /tmp/ollama-new $OLLAMA_BIN_PATH"
    ok "バイナリ差し替え完了"
  else
    err "バイナリ取得に失敗しました (ネットワーク確認、または dustynv バージョンのまま続行)"
    info "現在のバイナリのまま継続します"
  fi

  # Ollama サービスを再起動 (新バイナリを反映)
  info "Ollama サービスを再起動中..."
  sudo docker restart "$CONTAINER_NAME" > /dev/null 2>&1
  sleep 5
  for i in $(seq 1 15); do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
      ok "再起動完了"
      break
    fi
    sleep 2
  done

  OLLAMA_VER_AFTER=$(sudo docker exec "$CONTAINER_NAME" ollama --version 2>/dev/null || echo "?")
  info "適用後バイナリ: $OLLAMA_VER_AFTER"

  # 新バイナリのログで GPU 確認
  sleep 3
  echo ""
  if sudo docker logs "$CONTAINER_NAME" 2>&1 | grep -qiE "cuda|ggml_cuda|gpu layer"; then
    ok "✅ CUDA/GPU ログ確認 → GPU 動作中"
  else
    err "⚠️  CUDA ログ未確認"
    echo "    → ログ全体を確認: sudo docker logs ollama 2>&1 | grep -iE 'cuda|gpu'"
  fi
else
  head_ "5/6 バイナリ アップグレード"
  info "スキップ (--upgrade フラグなし)"
  info "GPU が動かない場合: bash scripts/fix_ollama_gpu.sh --upgrade"
fi

# ─── [6] GPU 動作検証 (実推論) ───────────────────────────────────────────────
head_ "6/6 GPU 動作検証 (推論でメモリ増加確認)"

MODELS=$(curl -s http://localhost:11434/api/tags 2>/dev/null | \
  python3 -c "
import sys, json
try:
    models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
    print('\n'.join(models))
except: pass
" 2>/dev/null || true)

if [ -z "$MODELS" ]; then
  info "テスト推論用モデルがありません"
  info "モデルを pull してから再確認:"
  echo "    # 例: qwen2.5:3b (小さくて速い)"
  echo "    curl -s -X POST http://localhost:11434/api/pull \\"
  echo "      -H 'Content-Type: application/json' \\"
  echo "      -d '{\"name\": \"qwen2.5:3b\"}'"
  echo ""
  ok "コンテナ再作成完了。モデル pull 後に GPU メモリ増加を確認してください"
else
  TEST_MODEL=$(echo "$MODELS" | head -1)
  info "テストモデル: $TEST_MODEL"
  echo ""

  GPU_BEFORE=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "?")
  info "GPU メモリ (推論前): ${GPU_BEFORE} MiB"

  info "推論中... (最大60秒)"
  RESPONSE=$(curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$TEST_MODEL\", \"prompt\": \"1+1=?\", \"stream\": false}" \
    --max-time 60 2>/dev/null | \
    python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    resp = d.get('response', '').strip()[:60]
    dur = d.get('eval_duration', 0)
    ntok = d.get('eval_count', 0)
    tps = ntok / (dur / 1e9) if dur > 0 else 0
    print(f'応答: {resp}')
    print(f'速度: {tps:.1f} t/s ({ntok} tokens)')
except Exception as e:
    print(f'パースエラー: {e}')
" 2>/dev/null || echo "推論失敗")

  GPU_AFTER=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "?")

  echo ""
  echo "$RESPONSE"
  echo ""
  info "GPU メモリ (推論後): ${GPU_AFTER} MiB"

  if [ "$GPU_BEFORE" != "?" ] && [ "$GPU_AFTER" != "?" ]; then
    GPU_DIFF=$((GPU_AFTER - GPU_BEFORE))
    if [ "$GPU_DIFF" -gt 200 ]; then
      ok "✅ GPU 動作確認: +${GPU_DIFF} MiB のメモリ割り当て → GPU 推論中"
    elif [ "$GPU_DIFF" -gt 50 ]; then
      ok "⚠️  GPU メモリ増加 +${GPU_DIFF} MiB (部分的 GPU 使用の可能性)"
    else
      err "❌ GPU メモリ変化が少ない (+${GPU_DIFF} MiB) → CPU 推論の可能性が高い"
      echo ""
      echo "  次の手順を試してください:"
      echo "    1. bash scripts/fix_ollama_gpu.sh --upgrade  (Ollama バイナリ更新)"
      echo "    2. sudo docker logs ollama 2>&1 | grep -iE 'cuda|gpu|layer'"
      echo "    3. sudo docker exec ollama nvidia-smi  (GPU アクセス確認)"
    fi
  fi
fi

echo ""
echo "════════════════════════════════════════════════════"
ok "完了"
echo ""
echo "  GPU 診断のみ:    bash scripts/fix_ollama_gpu.sh --diag"
echo "  バイナリ更新も:  bash scripts/fix_ollama_gpu.sh --upgrade"
echo "  Ollama ログ:     sudo docker logs -f ollama"
echo "  GPU 監視:        watch -n1 'nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader'"
echo "════════════════════════════════════════════════════"
