#!/bin/bash
# setup/10_setup_fan.sh - Jetson ファン冷却設定
#
# 問題: nvfancontrol が "quiet" プロファイルで動いており
#       LLM 推論中の発熱に対してファンが全然回っていない
#
# 解決:
#   1. sysfs の全 pwm パスを網羅的に検索 (Jetson モデルごとに異なる)
#   2. nvfancontrol を停止してファン PWM を手動設定 (積極冷却)
#   3. 起動時に自動適用する systemd サービスを登録
#   4. jetson_clocks --fan も試みる (フォールバック)
#
# 使い方:
#   bash setup/10_setup_fan.sh           # 推奨設定で適用 (PWM 200/255 = 78%)
#   bash setup/10_setup_fan.sh --max     # 最大 (PWM 255/255 = 100%)
#   bash setup/10_setup_fan.sh --status  # 現在の状態確認のみ
#   bash setup/10_setup_fan.sh --scan    # sysfs スキャンのみ (変更なし)
#
# 元に戻す:
#   sudo systemctl disable --now jetson-fan-cool
#   sudo systemctl enable --now nvfancontrol

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
info()  { echo -e "${YELLOW}[--]${NC} $*"; }
err()   { echo -e "${RED}[NG]${NC} $*"; }
head_(){ echo -e "\n${CYAN}${BOLD}── $* ──${NC}"; }

MODE="default"
FAN_PWM_TARGET=200   # 78% — LLM 推論中の積極冷却
for arg in "$@"; do
  case "$arg" in
    --max)    MODE="max";    FAN_PWM_TARGET=255 ;;
    --status) MODE="status" ;;
    --scan)   MODE="scan" ;;
  esac
done

echo ""
echo "════════════════════════════════════════════════"
echo "  🌀 Jetson ファン冷却設定"
echo "════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════
# ファン PWM パス検索 (Jetson モデルごとに異なる)
# ═══════════════════════════════════════════════════════════
find_all_fan_pwm() {
  local found=()

  # --- 既知パス (Jetson Orin / AGX / Xavier / Nano) -------------------------
  local candidates=(
    # Orin Nano / Orin NX / AGX Orin
    "/sys/devices/platform/pwm-fan/hwmon/hwmon0/pwm1"
    "/sys/devices/platform/pwm-fan/hwmon/hwmon1/pwm1"
    "/sys/devices/platform/pwm-fan/hwmon/hwmon2/pwm1"
    "/sys/devices/platform/pwm-fan/hwmon/hwmon3/pwm1"
    # Orin Nano Super / NX Super (別パス)
    "/sys/devices/platform/bus@0/3280000.tachometer/hwmon/hwmon0/pwm1"
    "/sys/devices/platform/bus@0/3280000.tachometer/hwmon/hwmon1/pwm1"
    # Xavier / AGX Xavier
    "/sys/devices/platform/pwm-fan.0/hwmon/hwmon0/pwm1"
    "/sys/devices/platform/pwm-fan.0/hwmon/hwmon1/pwm1"
  )

  for c in "${candidates[@]}"; do
    [ -f "$c" ] && found+=("$c")
  done

  # --- glob 展開 ---------------------------------------------------------------
  for p in \
    /sys/devices/platform/pwm-fan*/hwmon/hwmon*/pwm1 \
    /sys/devices/platform/bus@*/*/pwm-fan*/hwmon/hwmon*/pwm1 \
    /sys/devices/platform/bus@*/*.tachometer/hwmon/hwmon*/pwm1 \
    /sys/devices/pwm-fan*/hwmon/hwmon*/pwm1; do
    [ -f "$p" ] && found+=("$p")
  done

  # --- hwmon 全探索 (最終手段) -------------------------------------------------
  for p in /sys/class/hwmon/hwmon*/pwm1; do
    [ -f "$p" ] && found+=("$p")
  done

  # 重複を削除して返す
  printf '%s\n' "${found[@]}" | sort -u
}

# tegrastats からファン速度を取得
get_fan_speed_tegrastats() {
  if command -v tegrastats &>/dev/null; then
    local ts
    ts=$(timeout 2 tegrastats 2>/dev/null | head -1 || echo "")
    # "FAN [speed%]" の形式から抽出
    echo "$ts" | grep -oP 'FAN \[\K[^\]]+' 2>/dev/null || echo ""
  fi
}

# ─── [SCAN] sysfs スキャン ────────────────────────────────────────────────────
scan_fan_paths() {
  head_ "sysfs ファン PWM スキャン"
  echo ""

  echo "  全 pwm ファイルを検索中..."
  local all_pwm
  all_pwm=$(find /sys -name "pwm*" -type f 2>/dev/null | grep -v '/proc' | sort || true)
  if [ -z "$all_pwm" ]; then
    err "pwm ファイルが見つかりません"
  else
    ok "見つかった pwm ファイル:"
    echo "$all_pwm" | sed 's/^/    /'
  fi

  echo ""
  echo "  hwmon デバイス一覧:"
  for d in /sys/class/hwmon/hwmon*; do
    [ -d "$d" ] || continue
    local name=""
    [ -f "$d/name" ] && name=$(cat "$d/name" 2>/dev/null || echo "?")
    echo "    $(basename $d): $name"
    ls "$d"/pwm* 2>/dev/null | sed 's/^/      /' || true
  done

  echo ""
  local fan_speed
  fan_speed=$(get_fan_speed_tegrastats)
  [ -n "$fan_speed" ] && echo "  tegrastats ファン速度: $fan_speed" || true

  echo ""
  info "有効なファン PWM パスの候補:"
  find_all_fan_pwm | while read -r p; do
    echo "    $p = $(cat "$p" 2>/dev/null || echo '?')"
  done || echo "    候補なし"
}

# ─── [STATUS] 現在の状態を表示 ────────────────────────────────────────────────
show_status() {
  head_ "ファン状態確認"
  echo ""

  # PWM パス
  local all_paths
  all_paths=$(find_all_fan_pwm)
  if [ -z "$all_paths" ]; then
    err "ファン PWM パスが見つかりません"
    echo ""
    echo "  詳細スキャン:"
    echo "    bash setup/10_setup_fan.sh --scan"
    echo ""
    echo "  手動確認:"
    echo "    find /sys -name 'pwm*' -type f 2>/dev/null | head -20"
  else
    echo "  検出された PWM パス:"
    echo "$all_paths" | while read -r p; do
      local val pct
      val=$(cat "$p" 2>/dev/null || echo "?")
      if [ "$val" != "?" ] && [ -n "$val" ]; then
        pct=$(( val * 100 / 255 ))
        if [ "$val" -ge 180 ]; then
          echo -e "    ${GREEN}✅${NC} $p = $val/255 (${pct}%) [積極冷却]"
        elif [ "$val" -ge 100 ]; then
          echo -e "    ${YELLOW}⚠️ ${NC} $p = $val/255 (${pct}%) [中速]"
        else
          echo -e "    ${RED}❌${NC} $p = $val/255 (${pct}%) [低速・停止]"
        fi
      fi
    done
  fi

  # nvfancontrol
  echo ""
  if systemctl is-active nvfancontrol >/dev/null 2>&1; then
    echo -e "  nvfancontrol : ${RED}稼働中${NC} (quiet プロファイルが PWM を上書き中)"
  elif systemctl is-enabled nvfancontrol >/dev/null 2>&1; then
    echo -e "  nvfancontrol : ${YELLOW}停止 (有効)${NC} → 再起動後に quiet で復活する可能性"
  else
    echo -e "  nvfancontrol : ${GREEN}停止・無効${NC} (手動制御中)"
  fi

  # jetson-fan-cool サービス
  if systemctl is-active jetson-fan-cool >/dev/null 2>&1; then
    echo -e "  jetson-fan-cool : ${GREEN}稼働中 (永続設定済み)${NC}"
  else
    echo -e "  jetson-fan-cool : 未設定"
  fi

  # tegrastats からファン速度
  local fan_speed
  fan_speed=$(get_fan_speed_tegrastats)
  [ -n "$fan_speed" ] && echo "  tegrastats FAN : $fan_speed"

  # 温度
  echo ""
  echo "  現在の温度:"
  # Jetson の thermal_zone
  for tz in /sys/class/thermal/thermal_zone*; do
    [ -d "$tz" ] || continue
    local temp_file="$tz/temp"
    local type_file="$tz/type"
    [ -f "$temp_file" ] || continue
    local temp type
    temp=$(cat "$temp_file" 2>/dev/null || echo "0")
    type=$(cat "$type_file" 2>/dev/null || echo "unknown")
    if [[ "$type" == *CPU* ]] || [[ "$type" == *GPU* ]] || [[ "$type" == *SOC* ]] || [[ "$type" == *cpu* ]] || [[ "$type" == *gpu* ]]; then
      printf "    %-20s : %.1f°C\n" "$type" "$(echo "$temp" | awk '{print $1/1000}')"
    fi
  done
  nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | \
    awk '{printf "    %-20s : %s°C\n", "GPU (nvidia-smi)", $1}' || true
}

# ─── スキャン / ステータスのみ ────────────────────────────────────────────────
if [ "$MODE" = "scan" ]; then
  scan_fan_paths
  echo ""
  exit 0
fi

if [ "$MODE" = "status" ]; then
  show_status
  echo ""
  exit 0
fi

# ─── [1] 現状確認 ─────────────────────────────────────────────────────────────
head_ "1/5 現在の状態"
show_status

# ─── [2] PWM パスを決定 ───────────────────────────────────────────────────────
head_ "2/5 ファン PWM パス決定"
echo ""

ALL_PWM_PATHS=$(find_all_fan_pwm)

if [ -z "$ALL_PWM_PATHS" ]; then
  err "ファン PWM パスが見つかりません"
  echo ""
  echo "  詳細スキャンを実行:"
  scan_fan_paths
  echo ""
  echo "  もし上記でも見つからない場合:"
  echo "    find /sys -name 'pwm*' 2>/dev/null"
  echo ""
  echo "  代替: jetson_clocks でファンを最大化する場合:"
  echo "    sudo jetson_clocks --fan"
  echo ""
  # jetson_clocks --fan フォールバック
  if command -v jetson_clocks &>/dev/null; then
    info "jetson_clocks --fan でフォールバック試行..."
    sudo jetson_clocks --fan 2>/dev/null && ok "jetson_clocks --fan: 適用" || err "jetson_clocks --fan: 失敗"
  fi
  exit 1
fi

# 全パスを表示
echo "  検出された PWM パス:"
echo "$ALL_PWM_PATHS" | while read -r p; do
  local_val=$(cat "$p" 2>/dev/null || echo "?")
  echo "    $p  (現在値: $local_val)"
done

# 最初の有効パスを主パスに
FAN_PWM=$(echo "$ALL_PWM_PATHS" | head -1)
ok "使用するパス: $FAN_PWM"

# ─── [3] nvfancontrol を停止・無効化 ─────────────────────────────────────────
head_ "3/5 nvfancontrol 停止・無効化"
echo ""

if systemctl is-active nvfancontrol >/dev/null 2>&1; then
  info "nvfancontrol を停止中..."
  sudo systemctl stop nvfancontrol 2>/dev/null && ok "nvfancontrol 停止" || true
else
  ok "nvfancontrol は既に停止しています"
fi

if systemctl is-enabled nvfancontrol >/dev/null 2>&1; then
  info "nvfancontrol を無効化中 (再起動後も quiet に戻らないように)..."
  sudo systemctl disable nvfancontrol 2>/dev/null && ok "nvfancontrol 無効化" || true
else
  ok "nvfancontrol は既に無効化されています"
fi

# ─── [4] 全 PWM パスを設定 ────────────────────────────────────────────────────
head_ "4/5 ファン PWM 設定 (${FAN_PWM_TARGET}/255 = $((FAN_PWM_TARGET * 100 / 255))%)"
echo ""

PWM_SET_SUCCESS=false
echo "$ALL_PWM_PATHS" | while read -r p; do
  # 手動制御モードに切り替え
  sudo sh -c "echo 1 > ${p}_enable" 2>/dev/null || true
  # PWM 設定
  if sudo sh -c "echo $FAN_PWM_TARGET > $p" 2>/dev/null; then
    local_val=$(cat "$p" 2>/dev/null || echo "?")
    ok "$p → $local_val / 255 ($((local_val * 100 / 255))%)"
    PWM_SET_SUCCESS=true
  else
    err "$p → 書き込み失敗"
  fi
done

# jetson_clocks でもファン設定 (jetson_clocks は PWM を 255 にリセットする場合がある)
if command -v jetson_clocks &>/dev/null; then
  info "jetson_clocks 適用中 (クロック最大化)..."
  sudo jetson_clocks 2>/dev/null || true
  # jetson_clocks が PWM を上書きした場合は再設定
  echo "$ALL_PWM_PATHS" | while read -r p; do
    sudo sh -c "echo 1 > ${p}_enable" 2>/dev/null || true
    sudo sh -c "echo $FAN_PWM_TARGET > $p" 2>/dev/null || true
  done
  ok "jetson_clocks 適用 + PWM 再設定"
fi

# jetson_clocks --fan (確認・補強)
if command -v jetson_clocks &>/dev/null; then
  sudo jetson_clocks --show 2>/dev/null | grep -i fan | sed 's/^/  /' || true
fi

# ─── [5] 起動時に自動適用する systemd サービスを登録 ─────────────────────────
head_ "5/5 永続設定 (systemd サービス登録)"
echo ""

# 全パスに対応した ExecStart を生成
FAN_EXEC=""
while IFS= read -r p; do
  FAN_EXEC+="ExecStart=/bin/bash -c 'echo 1 > ${p}_enable 2>/dev/null; echo $FAN_PWM_TARGET > $p 2>/dev/null'\n"
done <<< "$ALL_PWM_PATHS"

sudo tee /etc/systemd/system/jetson-fan-cool.service > /dev/null << SYSTEMD_EOF
[Unit]
Description=Jetson Fan Aggressive Cooling (LLM Workload)
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
$(echo -e "$FAN_EXEC")
ExecStop=/bin/bash -c 'echo 2 > ${FAN_PWM}_enable 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

sudo systemctl daemon-reload
sudo systemctl enable jetson-fan-cool.service 2>/dev/null && ok "jetson-fan-cool.service 有効化"
sudo systemctl start  jetson-fan-cool.service 2>/dev/null && ok "jetson-fan-cool.service 起動"

# ─── 完了 ─────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
ok "ファン冷却設定完了"
echo ""
echo "  設定値 : PWM $FAN_PWM_TARGET / 255 ($((FAN_PWM_TARGET * 100 / 255))%)"
echo "  制御   : 手動 (nvfancontrol 無効)"
echo "  永続化 : jetson-fan-cool.service (boot 時自動適用)"
echo ""
echo "  状態確認:"
echo "    bash setup/10_setup_fan.sh --status"
echo ""
echo "  温度・ファン リアルタイム監視:"
echo "    watch -n2 \"tegrastats 2>/dev/null | head -1\""
echo "    watch -n1 nvidia-smi"
echo ""
echo "  元の quiet に戻す:"
echo "    sudo systemctl disable --now jetson-fan-cool"
echo "    sudo systemctl enable --now nvfancontrol"
echo "════════════════════════════════════════════════"
