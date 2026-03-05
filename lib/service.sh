#!/bin/bash
# lib/service.sh - サービス管理メニュー

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"

LLAMACPP_SERVER_PORT=8081
LLAMACPP_BIN="$HOME/llama.cpp/build/bin"
GGUF_DIR="$HOME/.ollama/models/lfm25_gguf"

menu_service() {
  while true; do
    # ヘッダ: Ollama と llama-server の状態
    local ollama_st="⏹️ 停止"
    check_ollama 2>/dev/null && ollama_st="✅ 稼働中"
    local lls_st="⏹️ 停止"
    curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok" && lls_st="✅ 稼働中"

    local choice
    choice=$(ui_menu "🚀 サービス管理  [Ollama: $ollama_st  |  llama-server: $lls_st]" \
      "1" "📊 ステータス    — GPU使用率・モデル・メモリ" \
      "2" "▶️  起動          — Ollama (GPU最適化込み)" \
      "3" "⏹️  停止" \
      "4" "🔄 再起動" \
      "5" "💬 チャット      — モデル選択 → 対話" \
      "6" "📜 ログ表示" \
      "B" "← 戻る"
    ) || return

    case "$choice" in
      1) _service_status ;;
      2) _ollama_start ;;
      3) _ollama_stop ;;
      4) _ollama_restart ;;
      5) _ollama_run_interactive ;;
      6) _service_logs ;;
      B) return ;;
    esac
  done
}

# Docker コンテナ "ollama" が存在するか確認する
_ollama_is_docker() {
  sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"
}

# GPU/CPU 最適化を暗黙適用 (全起動関数から呼ぶ)
# - MAXN 電源モード (nvpmodel -m 0)
# - クロック固定   (jetson_clocks)
# - ページキャッシュ解放 (drop_caches)
_apply_perf_mode() {
  # MAXN モード ID をボード設定から取得 (Orin Nano Super は 0 番でない場合がある)
  local maxn_id
  maxn_id=$(grep -i "POWER_MODEL" /etc/nvpmodel.conf 2>/dev/null | grep -i "MAXN" | grep -o "ID=[0-9]*" | head -1 | cut -d= -f2)
  sudo nvpmodel -m "${maxn_id:-0}" 2>/dev/null || true
  sudo jetson_clocks     2>/dev/null || true
  sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
}

_service_status() {
  local report="=== サービスステータス ===\n\n"

  # ── Ollama ──────────────────────────────────────────────────────────────────
  if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"; then
    local cstatus cimage
    cstatus=$(sudo docker ps --filter "name=^ollama$" --format "{{.Status}}" 2>/dev/null)
    cimage=$(sudo docker ps --filter "name=^ollama$" --format "{{.Image}}" 2>/dev/null)
    report+="[Ollama]     ✅ 稼働中 ($cstatus)\n"
    report+="[イメージ]   $cimage\n"
    # GPU env 確認
    local env
    env=$(sudo docker inspect ollama --format '{{range .Config.Env}}{{.}} {{end}}' 2>/dev/null || true)
    if echo "$env" | grep -q "GGML_CUDA_NO_VMM=1"; then
      report+="[GPU env]    ✅ GGML_CUDA_NO_VMM=1 設定済み\n"
    else
      report+="[GPU env]    ❌ GGML_CUDA_NO_VMM=1 未設定 → Setup → GPU修正 を実行\n"
    fi
  elif _ollama_is_docker; then
    report+="[Ollama]     ⏹️ 停止中 (コンテナ存在)\n"
  else
    report+="[Ollama]     ℹ️ コンテナなし → Setup → 初回セットアップ\n"
  fi

  if check_ollama 2>/dev/null; then
    local models_count running
    models_count=$(get_models 2>/dev/null | wc -l || echo "?")
    report+="[API]        ✅ 応答あり (モデル: ${models_count}件)\n"
    running=$(curl -s http://localhost:11434/api/ps 2>/dev/null | \
      python3 -c "
import sys,json
try:
    for m in json.load(sys.stdin).get('models',[]):
        mb = m.get('size_vram',0)//1048576
        print(f\"  {m['name']} ({mb}MB VRAM)\")
except: pass
" 2>/dev/null || true)
    if [ -n "$running" ]; then
      report+="[実行中]     \n$running\n"
    fi
  else
    report+="[API]        ⚠️  応答なし (port 11434)\n"
  fi

  # ── llama-server ────────────────────────────────────────────────────────────
  report+="\n"
  if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    local pid
    pid=$(cat /tmp/llama-server.pid 2>/dev/null || echo "?")
    report+="[llama-srv]  ✅ 稼働中 port $LLAMACPP_SERVER_PORT (PID: $pid)\n"
  else
    report+="[llama-srv]  ⏹️ 停止\n"
  fi

  # ── GPU / メモリ ─────────────────────────────────────────────────────────────
  report+="\n=== GPU / メモリ ===\n"
  local gpu_info
  gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
    --format=csv,noheader 2>/dev/null | \
    awk -F',' '{printf "GPU使用率:%s  VRAM:%s/%s  温度:%s\n",$1,$2,$3,$4}' || echo "nvidia-smi 取得失敗")
  report+="$gpu_info\n"
  report+="$(free -h | head -2)\n"

  # ── Tegrastats ──────────────────────────────────────────────────────────────
  if command -v tegrastats &>/dev/null; then
    local tstat
    tstat=$(timeout 2 tegrastats 2>/dev/null | head -1 || echo "取得失敗")
    report+="\n=== Tegrastats ===\n$tstat\n"
  fi

  # ── 電源モード ───────────────────────────────────────────────────────────────
  local power_mode
  power_mode=$(sudo nvpmodel -q 2>/dev/null | grep "NV Power Mode" | awk '{print $NF}' || echo "?")
  report+="\n電源モード: $power_mode"

  whiptail --title "$TITLE - ステータス" \
    --scrolltext \
    --msgbox "$report" $HEIGHT $WIDTH
}

# ログ表示: Ollama + llama-server を選択して表示
_service_logs() {
  local choice
  choice=$(ui_menu "📜 ログ表示" \
    "1" "Ollama コンテナログ (docker logs)" \
    "2" "llama-server ログ (/tmp/llama-server.log)" \
    "B" "← 戻る"
  ) || return

  case "$choice" in
    1) _ollama_logs ;;
    2) _llamacpp_logs ;;
  esac
}

_ollama_start() {
  if check_ollama; then
    ui_msg "Ollama" "Ollamaは既に起動しています"
    return
  fi

  if ! _ollama_is_docker; then
    ui_error "Ollama コンテナが見つかりません\n\nまず Setup → jetson-containers セットアップを実行してください"
    return
  fi

  ui_info "Ollama (Docker) を起動中...\nMAXN 電源モード + クロック固定 + メモリ解放を適用します"
  _apply_perf_mode
  sudo docker start ollama > /dev/null 2>&1

  local i=0
  while [ $i -lt 10 ]; do
    if check_ollama; then
      ui_success "Ollama が起動しました！\nAPI: http://localhost:11434"
      return
    fi
    sleep 3
    i=$((i + 1))
  done
  ui_error "起動に失敗しました\nログ: sudo docker logs ollama"
}

_ollama_stop() {
  ui_confirm "Ollamaを停止しますか？" || return

  # ロード中モデルを API 経由でアンロード (keep_alive=0)
  local running
  running=$(curl -s http://localhost:11434/api/ps 2>/dev/null | \
    python3 -c "
import sys, json
try:
    for m in json.load(sys.stdin).get('models', []):
        print(m['name'])
except:
    pass
" 2>/dev/null || true)
  for model in $running; do
    curl -s -X POST http://localhost:11434/api/generate \
      -d "{\"model\": \"$model\", \"keep_alive\": 0}" > /dev/null 2>&1 || true
  done

  if _ollama_is_docker; then
    sudo docker stop ollama > /dev/null 2>&1
  fi

  sleep 1
  if ! check_ollama; then
    ui_success "Ollama を停止しました"
  else
    ui_error "停止に失敗しました"
  fi
}

_ollama_restart() {
  ui_info "Ollamaを再起動中...\nMAXN 電源モード + クロック固定 + メモリ解放を適用します"
  if _ollama_is_docker; then
    sudo docker stop ollama > /dev/null 2>/dev/null || true
    sleep 1
    _apply_perf_mode
    sudo docker start ollama > /dev/null 2>&1
    sleep 3
  else
    ui_error "Ollama コンテナが見つかりません\nSetup → jetson-containers セットアップを実行してください"
    return
  fi

  if check_ollama; then
    ui_success "Ollama が再起動しました"
  else
    ui_error "再起動に失敗しました\nログ: sudo docker logs ollama"
  fi
}

_ollama_logs() {
  local tmpfile
  tmpfile=$(mktemp)

  if _ollama_is_docker; then
    sudo docker logs --tail 50 ollama > "$tmpfile" 2>&1
  else
    echo "Ollama コンテナが見つかりません" > "$tmpfile"
  fi

  whiptail --title "$TITLE - Ollamaログ (最新50行)" \
    --scrolltext \
    --textbox "$tmpfile" $HEIGHT $WIDTH

  rm -f "$tmpfile"
}

_ollama_run_interactive() {
  if ! check_ollama; then
    ui_error "Ollama API が応答しません\nまず Ollama を起動してください (項目 2)"
    return
  fi

  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_error "モデルがインストールされていません\nModels メニューから pull してください"
    return
  fi

  local items=()
  while IFS= read -r m; do
    items+=("$m" "")
  done <<< "$models"

  local target
  target=$(ui_menu "💬 チャットするモデルを選択" "${items[@]}") || return

  clear
  bash "$SCRIPT_DIR/ollama-run.sh" "$target"
  press_any_key
}

_container_update() {
  if ! command -v autotag &>/dev/null; then
    ui_error "autotag が見つかりません\nSetup → jetson-containers セットアップを先に実行してください"
    return
  fi

  local new_image
  new_image=$(autotag ollama 2>/dev/null || true)
  if [ -z "$new_image" ]; then
    ui_error "autotag でイメージを解決できませんでした\nJetPack バージョンを確認してください"
    return
  fi

  local current_image=""
  if _ollama_is_docker; then
    current_image=$(sudo docker inspect ollama --format '{{.Config.Image}}' 2>/dev/null || true)
  fi

  ui_confirm "コンテナイメージを更新します\n\n現在: ${current_image:-不明}\n新規: $new_image\n\n既存コンテナを停止・削除して再作成します。よろしいですか？" || return

  clear
  echo "── [1/4] イメージをダウンロード中: $new_image ──"
  sudo docker pull "$new_image"

  echo ""
  echo "── [2/4] 既存コンテナを停止・削除 ──"
  sudo docker stop ollama 2>/dev/null || true
  _apply_perf_mode
  sudo docker rm ollama 2>/dev/null || true

  echo ""
  echo "── [3/4] 新しいコンテナを起動 ──"
  mkdir -p "$HOME/.ollama/models"
  sudo docker run -d \
    --name ollama \
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
    "$new_image" \
    /bin/sh -c '/start_ollama; tail -f /data/logs/ollama.log'

  echo ""
  echo "── [4/4] API 応答待ち ──"
  local i=0
  while [ $i -lt 10 ]; do
    if check_ollama; then
      ui_success "コンテナイメージの更新が完了しました\n\nイメージ: $new_image\nAPI: http://localhost:11434"
      return
    fi
    sleep 3
    i=$((i + 1))
  done
  ui_error "API が応答しません\nログ: sudo docker logs ollama"
}

_api_test() {
  if ! check_ollama; then
    ui_error "OllamaのAPIが応答しません\nまずOllamaを起動してください"
    return
  fi

  local models
  models=$(get_models)
  if [ -z "$models" ]; then
    ui_error "モデルがインストールされていません"
    return
  fi

  local items=()
  while IFS= read -r m; do
    items+=("$m" "")
  done <<< "$models"

  local target
  target=$(ui_menu "テストに使うモデルを選択" "${items[@]}") || return

  ui_info "API テスト中...\n\ncurl http://localhost:11434/v1/chat/completions"

  local response
  response=$(curl -s http://localhost:11434/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$target\", \"messages\": [{\"role\": \"user\", \"content\": \"Hi! Reply in one sentence.\"}]}" \
    2>&1)

  local content
  content=$(echo "$response" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null \
    || echo "レスポンスのパースに失敗\n\nRAW:\n$response")

  whiptail --title "$TITLE - API テスト結果 ($target)" \
    --msgbox "✅ OpenAI互換APIが正常に応答しました\n\n応答:\n$content" \
    $HEIGHT $WIDTH
}

_tegrastats_monitor() {
  if ! command -v tegrastats &>/dev/null; then
    ui_error "tegrastats が見つかりません\nJetPackが正しくインストールされているか確認してください"
    return
  fi

  ui_msg "tegrastats モニタ" "Ctrl+C で終了します\n\nターミナルで tegrastats を起動します..."
  echo "--- tegrastats (Ctrl+C で停止) ---"
  tegrastats --interval 1000
  press_any_key
}

# ═══════════════════════════════════════════════════════════
# LFM-2.5 llama-server 管理
# ═══════════════════════════════════════════════════════════

_llamacpp_server_start() {
  if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    ui_msg "llama-server" "既に port $LLAMACPP_SERVER_PORT で稼働しています"
    return
  fi

  if [ ! -f "$LLAMACPP_BIN/llama-server" ]; then
    ui_error "llama.cpp がビルドされていません\n\nSetup → LFM-2.5 セットアップ を実行してください"
    return
  fi

  # CPU / GPU モード自動検出
  local use_gpu=false
  if ls "$LLAMACPP_BIN"/libggml-cuda.so* >/dev/null 2>&1; then
    use_gpu=true
  fi

  # GGUFファイルを選択
  local gguf_files
  gguf_files=$(ls "$GGUF_DIR"/*.gguf 2>/dev/null)
  if [ -z "$gguf_files" ]; then
    ui_error "GGUFファイルが見つかりません: $GGUF_DIR\n\nSetup → LFM-2.5 セットアップ を実行してください"
    return
  fi

  local items=()
  while IFS= read -r f; do
    items+=("$f" "$(basename "$f")")
  done <<< "$gguf_files"

  local target
  target=$(ui_menu "起動するモデル (GGUF) を選択" "${items[@]}") || return

  if $use_gpu; then
    ui_info "llama-server を起動中...\nGPU モード: MAXN + jetson_clocks + -ngl 999 + Flash Attention\nport: $LLAMACPP_SERVER_PORT"
  else
    ui_info "llama-server を起動中...\nCPU モード: -ngl 0 (GPU なし) — ~7 t/s\nGPU ビルドは: Setup → 4. llama.cpp ビルド単体\nport: $LLAMACPP_SERVER_PORT"
  fi

  # 既存プロセスを停止
  pkill -f "llama-server.*$LLAMACPP_SERVER_PORT" 2>/dev/null || true
  sleep 1

  # パフォーマンス最適化を暗黙適用
  _apply_perf_mode

  # 起動引数を組み立て (CPU/GPU 共通)
  local launch_args=(
    -m "$target"
    -c 4096
    -b 512 -ub 512
    -t 6
    --host 0.0.0.0
    --port "$LLAMACPP_SERVER_PORT"
    --verbose
  )

  if $use_gpu; then
    # ─── Jetson GPU 必須環境変数 ──────────────────────────────────────────
    # GGML_CUDA_NO_VMM=1  : Jetson は CUDA VMM 非対応。これなしで GPU 割り当て失敗
    # GGML_CUDA_FORCE_MMQ : Q4_K_M 量子化で CUDA 行列演算を強制 (+10~30% speed)
    export GGML_CUDA_NO_VMM=1
    export GGML_CUDA_FORCE_MMQ=1
    export GGML_CUDA_NO_PEER_COPY=1
    export CUDA_VISIBLE_DEVICES=0
    launch_args+=(-ngl 999 --flash-attn --cache-type-k q8_0 --cache-type-v q8_0)
  fi

  nohup "$LLAMACPP_BIN/llama-server" "${launch_args[@]}" \
    > /tmp/llama-server.log 2>&1 &
  echo $! > /tmp/llama-server.pid

  # 起動待機
  local i=0
  while [ $i -lt 20 ]; do
    if curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
      # ─── GPU 動作確認 ────────────────────────────────────────────────────
      local gpu_info=""
      if $use_gpu; then
        # ログで CUDA 初期化を確認
        local cuda_in_log="❓ 確認中"
        if grep -qi "cuda\|ggml_cuda\|gpu layers" /tmp/llama-server.log 2>/dev/null; then
          cuda_in_log="✅ CUDA ログあり"
        elif grep -qi "CPU\|cpu only" /tmp/llama-server.log 2>/dev/null; then
          cuda_in_log="⚠️  CPU ログ検出"
        fi
        # nvidia-smi で GPU メモリ確認
        local gpu_mem
        gpu_mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null | head -1 || echo "取得失敗")
        gpu_info="\n\n🔍 GPU 確認:\n  ログ: $cuda_in_log\n  GPU メモリ: $gpu_mem\n\n⚠️  GPU 未使用の場合:\n  bash scripts/fix_ollama_gpu.sh"
      fi
      ui_success "llama-server 起動完了！\n\nAPI: http://localhost:$LLAMACPP_SERVER_PORT\nモデル: $(basename "$target")\nログ: /tmp/llama-server.log${gpu_info}"
      return
    fi
    sleep 1
    i=$((i + 1))
  done

  # 起動失敗 — ログを表示して原因特定
  local fail_log=""
  if [ -f /tmp/llama-server.log ]; then
    fail_log="\n\nログ (最新10行):\n$(tail -10 /tmp/llama-server.log 2>/dev/null)"
  fi
  ui_error "起動に失敗しました${fail_log}\n\n確認: tail -f /tmp/llama-server.log"
}

_llamacpp_server_stop() {
  if ! curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    ui_msg "llama-server" "稼働していません"
    return
  fi

  ui_confirm "llama-server を停止しますか？" || return

  local pid
  pid=$(cat /tmp/llama-server.pid 2>/dev/null)
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
  fi
  pkill -f "llama-server.*$LLAMACPP_SERVER_PORT" 2>/dev/null || true

  sleep 1
  if ! curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    ui_success "llama-server を停止しました"
  else
    ui_error "停止に失敗しました"
  fi
}

_llamacpp_api_test() {
  if ! curl -s "http://localhost:$LLAMACPP_SERVER_PORT/health" 2>/dev/null | grep -q "ok"; then
    ui_error "llama-server が起動していません\n(L1) LFM-2.5 llama-server 起動 を実行してください"
    return
  fi

  local prompt
  prompt=$(ui_input "テストプロンプト" "日本語で自己紹介してください。") || return
  [ -z "$prompt" ] && return

  ui_info "LFM-2.5 で推論中...\n(10〜30秒かかります)"

  local result
  result=$(curl -s "http://localhost:$LLAMACPP_SERVER_PORT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json; print(json.dumps({
      'model': 'lfm2.5',
      'messages': [{'role': 'user', 'content': '$prompt'}]
    }))")" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'])
except Exception as e:
    print(f'パースエラー: {e}')
" 2>&1)

  whiptail --title "$TITLE - LFM-2.5 応答 (port $LLAMACPP_SERVER_PORT)" \
    --scrolltext \
    --msgbox "$result" $HEIGHT $WIDTH
}

_llamacpp_logs() {
  local logfile="/tmp/llama-server.log"
  if [ ! -f "$logfile" ]; then
    ui_msg "llama-server ログ" "ログファイルが見つかりません: $logfile\nまず llama-server を起動してください"
    return
  fi

  local tmpfile
  tmpfile=$(mktemp)
  tail -50 "$logfile" > "$tmpfile"
  whiptail --title "$TITLE - llama-server ログ (最新50行)" \
    --scrolltext \
    --textbox "$tmpfile" $HEIGHT $WIDTH
  rm -f "$tmpfile"
}
