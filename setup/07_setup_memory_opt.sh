#!/bin/bash
# setup/07_setup_memory_opt.sh - OS レベルメモリ最適化
#
# 参考: https://bone.jp/articles/2025/250125_JetsonOrinNanoSuper_4_memory
#
# 実施内容:
#   1. ディスク空き容量チェック (≥18GB)
#   2. SSD スワップファイル作成 (16GB)
#   3. /etc/fstab への永続化
#   4. ZRAM 無効化 (nvzramconfig) ※次回起動から有効
#   5. nvargus-daemon 無効化 (カメラデーモン)
#   [オプション] GUI 無効化 (multi-user.target)

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[--]${NC} $*"; }
err()  { echo -e "${RED}[NG]${NC} $*"; }

# ─── sudo チェック ────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  info "sudo 権限が必要です。パスワードを入力してください。"
  sudo -v || { err "sudo 権限を取得できませんでした"; exit 1; }
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo "  💾 メモリ最適化セットアップ"
echo "  (SSD スワップ / ZRAM 無効化 / nvargus 無効化)"
echo "══════════════════════════════════════════════════════"
echo ""

# ─── SSD マウントポイント検出 ─────────────────────────────────────────────────
_detect_ssd_mount() {
  # Priority 1: 専用 NVMe マウントポイントを探す
  for candidate in /ssd /mnt/ssd /mnt/nvme /data; do
    if mountpoint -q "$candidate" 2>/dev/null; then
      src=$(findmnt -n -o SOURCE "$candidate" 2>/dev/null || true)
      if echo "$src" | grep -q "nvme"; then
        echo "$candidate"; return 0
      fi
    fi
  done
  # Priority 2: NVMe が / にマウントされているケース (このシステムの実際の構成)
  root_src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  if echo "$root_src" | grep -q "nvme"; then
    echo "/"; return 0
  fi
  # フォールバック: eMMC 等
  echo "/"
}

SSD_MOUNT=$(_detect_ssd_mount)
if [ "$SSD_MOUNT" = "/" ]; then
  SWAP_FILE="/swapfile_16g"
else
  SWAP_FILE="${SSD_MOUNT}/16GB.swap"
fi

echo "  検出されたストレージ: $SSD_MOUNT"
echo "  スワップファイルパス: $SWAP_FILE"
echo ""

# ─── [1/5] ディスク空き容量チェック ─────────────────────────────────────────
echo "── [1/5] ディスク空き容量チェック ──"
# スワップ対象ディレクトリの空き容量を取得 (KB単位)
target_dir=$(dirname "$SWAP_FILE")
free_kb=$(df --output=avail "$target_dir" 2>/dev/null | tail -1 | tr -d ' ')
free_gb=$(( free_kb / 1024 / 1024 ))

echo "  対象: $target_dir (空き: ${free_gb}GB)"

# 既存スワップファイルがあれば空き容量チェックをスキップ
if [ -f "$SWAP_FILE" ]; then
  ok "スワップファイルは既に存在します (空き容量チェックをスキップ)"
else
  if [ "$free_gb" -lt 18 ]; then
    err "空き容量が不足しています: ${free_gb}GB (最低 18GB 必要)"
    err "不要なファイルを削除するか、別のディスクを確保してください"
    exit 1
  fi
  ok "空き容量確認: ${free_gb}GB (18GB 以上)"
fi

# ─── [2/5] SSD スワップファイル作成 ─────────────────────────────────────────
echo ""
echo "── [2/5] SSD スワップファイル作成 (16GB) ──"

# 既にスワップとして有効か確認
if swapon --show | grep -q "$SWAP_FILE"; then
  ok "スワップ既に有効: $SWAP_FILE"
else
  # ファイルが存在するが swapon されていない場合
  if [ -f "$SWAP_FILE" ]; then
    info "既存のスワップファイルを有効化します: $SWAP_FILE"
  else
    info "スワップファイルを作成中 (16GB)... しばらくかかります"
    # fallocate を試みる (高速)
    if sudo fallocate -l 16G "$SWAP_FILE" 2>/dev/null; then
      ok "fallocate で作成完了"
    else
      # fallocate が使えない場合 (例: XFS 以外) は dd にフォールバック
      info "fallocate 失敗 → dd にフォールバック (数分かかります)..."
      sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=16384 status=progress
      ok "dd で作成完了"
    fi
  fi

  sudo chmod 600 "$SWAP_FILE"
  sudo mkswap "$SWAP_FILE"
  sudo swapon "$SWAP_FILE"
  ok "スワップ有効化: $SWAP_FILE"
fi

# ─── [3/5] /etc/fstab への永続化 ────────────────────────────────────────────
echo ""
echo "── [3/5] /etc/fstab 永続化 ──"

if grep -qF "$SWAP_FILE" /etc/fstab; then
  ok "fstab エントリ既存: $SWAP_FILE"
else
  echo "$SWAP_FILE  none  swap  sw  0  0" | sudo tee -a /etc/fstab > /dev/null
  ok "fstab に追加: $SWAP_FILE  none  swap  sw  0  0"
fi

# ─── [4/5] ZRAM 無効化 ───────────────────────────────────────────────────────
echo ""
echo "── [4/5] ZRAM 無効化 (nvzramconfig) ──"
# 注意: 現在の ZRAM デバイスを swapoff するとメモリ不足 (OOM) になる可能性があるため、
# サービスを無効化して次回起動時から ZRAM を使わないようにする。

if systemctl list-unit-files nvzramconfig.service 2>/dev/null | grep -q "nvzramconfig"; then
  status_enabled=$(systemctl is-enabled nvzramconfig 2>/dev/null || echo "not-found")
  if [ "$status_enabled" = "disabled" ]; then
    ok "nvzramconfig.service は既に無効化済みです"
  else
    sudo systemctl disable nvzramconfig.service
    ok "nvzramconfig.service を無効化しました (次回起動から ZRAM なし)"
    info "※ 現在の ZRAM スワップは OOM 防止のため今すぐは解除しません"
    info "  次回再起動後に SSD スワップに切り替わります"
  fi
else
  info "nvzramconfig.service が見つかりません (スキップ)"
fi

# ─── [5/5] nvargus-daemon 無効化 ────────────────────────────────────────────
echo ""
echo "── [5/5] nvargus-daemon 無効化 (カメラデーモン) ──"

svc="nvargus-daemon"
is_active=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
is_enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")

if [ "$is_enabled" = "not-found" ] || [ "$is_enabled" = "static" ]; then
  info "$svc が見つからないか static です (スキップ)"
elif [ "$is_enabled" = "disabled" ] && [ "$is_active" = "inactive" ]; then
  ok "$svc は既に無効化済みです"
else
  sudo systemctl stop "$svc" 2>/dev/null || true
  sudo systemctl disable "$svc"
  ok "$svc を停止・無効化しました"
fi

# ─── [オプション] GUI 無効化 ─────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  [オプション] デスクトップ GUI の無効化"
echo "══════════════════════════════════════════════════════"
echo ""

current_target=$(systemctl get-default 2>/dev/null || echo "unknown")
echo "  現在のデフォルトターゲット: $current_target"
echo ""

if [ "$current_target" = "multi-user.target" ]; then
  ok "既に multi-user.target です (GUI は無効化済み)"
else
  echo "  GUI を無効化すると約 300MB の RAM を節約できます。"
  echo "  SSH やシリアルコンソールでアクセスしている場合に有効です。"
  echo ""
  echo "  ※ 元に戻すには: sudo systemctl set-default graphical.target && sudo reboot"
  echo ""
  read -r -p "  GUI を無効化しますか？ [y/N] " gui_ans
  case "$gui_ans" in
    [Yy]*)
      sudo systemctl set-default multi-user.target
      ok "GUI 無効化設定完了 (次回再起動から適用)"
      info "  再起動後にGUIに戻したい場合: sudo systemctl set-default graphical.target"
      ;;
    *)
      info "GUI は変更しません"
      ;;
  esac
fi

# ─── 完了バナー ───────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
ok "メモリ最適化セットアップ完了"
echo "══════════════════════════════════════════════════════"
echo ""
echo "  【メモリ状況】"
free -h
echo ""
echo "  【スワップ状況】"
swapon --show
echo ""
echo "  次回再起動後の変更:"
echo "    - ZRAM スワップ → SSD スワップ (16GB) に切り替わります"
if [ "$current_target" != "multi-user.target" ] && [[ "${gui_ans:-n}" =~ ^[Yy] ]]; then
  echo "    - GUI (graphical.target) が無効化されます"
fi
echo ""
