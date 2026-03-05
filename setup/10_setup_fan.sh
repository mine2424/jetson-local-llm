#!/bin/bash
# setup/10_setup_fan.sh - Jetson ファン冷却設定
#
# 問題: nvfancontrol が "quiet" プロファイルで動いており
#       LLM 推論中の発熱に対してファンが全然回っていない
#
# 解決:
#   1. nvfancontrol を停止（quiet プロファイルの上書きを防ぐ）
#   2. sysfs 経由でファン PWM を手動設定（積極的な冷却モード）
#   3. 起動時に自動適用する systemd サービスを登録
#
# 使い方:
#   bash setup/10_setup_fan.sh           # 推奨設定で適用 (PWM 200/255)
#   bash setup/10_setup_fan.sh --max     # 最大 (PWM 255/255 = 100%)
#   bash setup/10_setup_fan.sh --status  # 現在の状態確認のみ
#
# 元に戻す:
#   sudo systemctl enable --now nvfancontrol
#   sudo systemctl disable --now jetson-fan-cool

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
info()  { echo -e "${YELLOW}[--]${NC} $*"; }
err()   { echo -e "${RED}[NG]${NC} $*"; }
head_(){ echo -e "${CYAN}── $* ──${NC}"; }

MODE="default"   # default | max | status
FAN_PWM_TARGET=200   # 78% — LLM 推論中の積極冷却
[[ "${1:-}" == "--max"    ]] && { MODE="max";    FAN_PWM_TARGET=255; }
[[ "${1:-}" == "--status" ]] && MODE="status"

echo ""
echo "════════════════════════════════════════════════"
echo "  🌀 Jetson ファン冷却設定"
echo "════════════════════════════════════════════════"
echo ""

# ─── ファン PWM パスを動的に探す ────────────────────────────────────────────────
find_fan_pwm() {
  # Jetson Orin Nano の主パス
  local p
  p=$(ls /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1 2>/dev/null | head -1)
  [ -n "$p" ] && { echo "$p"; return 0; }

  # 代替: 全 hwmon を検索
  for f in /sys/class/hwmon/hwmon*/pwm1; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done

  # Orin の別パス
  p=$(ls /sys/devices/platform/bus@0/2200000.gpio/hwmon/hwmon*/pwm1 2>/dev/null | head -1)
  [ -n "$p" ] && { echo "$p"; return 0; }

  echo ""
}

FAN_PWM=$(find_fan_pwm)

# ─── [STATUS] 現在の状態を表示 ──────────────────────────────────────────────────
show_status() {
  head_ "ファン状態"

  # PWM 値
  if [ -n "$FAN_PWM" ] && [ -f "$FAN_PWM" ]; then
    local pwm_val enable_val
    pwm_val=$(cat "$FAN_PWM" 2>/dev/null || echo "?")
    enable_val=$(cat "${FAN_PWM}_enable" 2>/dev/null || echo "?")
    local pct=$(( pwm_val * 100 / 255 ))
    ok "ファン PWM パス: $FAN_PWM"
    echo "  現在の PWM: $pwm_val / 255 (${pct}%)"
    case "$enable_val" in
      0) echo "  制御モード : 0 = 無効 (ファン停止)" ;;
      1) echo "  制御モード : 1 = 手動" ;;
      2) echo "  制御モード : 2 = 自動 (カーネル thermal)" ;;
      *) echo "  制御モード : $enable_val" ;;
    esac
  else
    err "ファン PWM パスが見つかりません"
    echo "  手動確認: ls /sys/class/hwmon/"
  fi

  # nvfancontrol
  echo ""
  if systemctl is-active nvfancontrol >/dev/null 2>&1; then
    echo -e "  nvfancontrol : ${RED}稼働中${NC} (quiet プロファイルを上書きしている可能性あり)"
  elif systemctl is-enabled nvfancontrol >/dev/null 2>&1; then
    echo -e "  nvfancontrol : 停止 (有効設定あり → 再起動後に復活する可能性)"
  else
    echo -e "  nvfancontrol : ${GREEN}停止・無効${NC} (手動制御中)"
  fi

  # jetson-fan-cool サービス
  if systemctl is-active jetson-fan-cool >/dev/null 2>&1; then
    echo -e "  jetson-fan-cool : ${GREEN}稼働中 (永続設定済み)${NC}"
  fi

  # GPU 温度
  echo ""
  head_ "現在の温度"
  local temps
  temps=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | \
    awk 'NR==1{printf "CPU/GPU: %.1f°C\n", $1/1000}')
  [ -n "$temps" ] && echo "  $temps"
  nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | \
    awk '{printf "  GPU (nvidia-smi): %s°C\n", $1}' || true
}

if [ "$MODE" = "status" ]; then
  show_status
  echo ""
  exit 0
fi

# ─── [1] 現状確認 ──────────────────────────────────────────────────────────────
head_ "1/4 現在の状態"
show_status
echo ""

if [ -z "$FAN_PWM" ]; then
  err "ファン PWM パスが見つかりません。手動で確認してください:"
  echo "  ls /sys/class/hwmon/"
  echo "  ls /sys/devices/platform/pwm-fan/"
  exit 1
fi

# ─── [2] nvfancontrol を停止・無効化 ───────────────────────────────────────────
head_ "2/4 nvfancontrol を停止"

if systemctl is-active nvfancontrol >/dev/null 2>&1; then
  info "nvfancontrol を停止中..."
  sudo systemctl stop nvfancontrol
  ok "nvfancontrol 停止"
else
  ok "nvfancontrol は既に停止しています"
fi

if systemctl is-enabled nvfancontrol >/dev/null 2>&1; then
  info "nvfancontrol を無効化中 (再起動後も quiet に戻らないように)..."
  sudo systemctl disable nvfancontrol 2>/dev/null || true
  ok "nvfancontrol 無効化"
fi

echo ""

# ─── [3] ファン PWM を手動設定 ────────────────────────────────────────────────
head_ "3/4 ファン PWM 設定 (${FAN_PWM_TARGET}/255 = $((FAN_PWM_TARGET * 100 / 255))%)"

# 手動制御に切り替え
sudo sh -c "echo 1 > ${FAN_PWM}_enable" 2>/dev/null || true

# PWM 設定
sudo sh -c "echo $FAN_PWM_TARGET > $FAN_PWM"

# 確認
local_pwm=$(cat "$FAN_PWM" 2>/dev/null || echo "?")
ok "ファン PWM: $local_pwm / 255 ($((local_pwm * 100 / 255))%)"

# jetson_clocks でもファンを最大化（併用）
if command -v jetson_clocks &>/dev/null; then
  info "jetson_clocks でファン設定を適用中..."
  sudo jetson_clocks 2>/dev/null || true
  # jetson_clocks が PWM を255にリセットする場合があるため再設定
  sudo sh -c "echo $FAN_PWM_TARGET > $FAN_PWM" 2>/dev/null || true
  ok "jetson_clocks 適用"
fi

echo ""

# ─── [4] 起動時に自動適用するサービスを登録 ──────────────────────────────────
head_ "4/4 永続設定 (systemd サービス登録)"

FAN_PWM_PATH_ESCAPED="${FAN_PWM//\//\\/}"

sudo tee /etc/systemd/system/jetson-fan-cool.service > /dev/null << EOF
[Unit]
Description=Jetson Fan Aggressive Cooling (LLM Workload)
After=multi-user.target nvfancontrol.service
Wants=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'echo 1 > ${FAN_PWM}_enable && echo $FAN_PWM_TARGET > $FAN_PWM'
ExecStop=/bin/bash -c 'echo 2 > ${FAN_PWM}_enable'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable jetson-fan-cool.service
sudo systemctl start jetson-fan-cool.service
ok "jetson-fan-cool.service 登録・起動"

# ─── 完了 ──────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
ok "ファン冷却設定完了"
echo ""
echo "  設定値:   PWM $FAN_PWM_TARGET / 255 ($((FAN_PWM_TARGET * 100 / 255))%)"
echo "  制御:     手動 (nvfancontrol 無効)"
echo "  永続化:   jetson-fan-cool.service (boot 時自動適用)"
echo ""
echo "  温度監視:"
echo "    watch -n 2 'cat /sys/class/thermal/thermal_zone*/temp | awk \"{print \$1/1000}\"'"
echo "    watch -n 1 nvidia-smi"
echo ""
echo "  元の quiet に戻す:"
echo "    sudo systemctl disable --now jetson-fan-cool"
echo "    sudo systemctl enable --now nvfancontrol"
echo "════════════════════════════════════════════════"
