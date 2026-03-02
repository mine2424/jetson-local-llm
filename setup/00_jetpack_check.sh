#!/bin/bash
# JetPack環境チェック
set -e

echo "=== Jetson Environment Check ==="
echo ""

# JetPack バージョン
echo "[JetPack Version]"
if [ -f /etc/nv_tegra_release ]; then
  cat /etc/nv_tegra_release
else
  echo "⚠️  /etc/nv_tegra_release not found"
fi
echo ""

# CUDA
echo "[CUDA]"
if command -v nvcc &>/dev/null; then
  nvcc --version | grep release
elif [ -x /usr/local/cuda/bin/nvcc ]; then
  /usr/local/cuda/bin/nvcc --version | grep release
else
  echo "⚠️  nvcc not found"
fi
echo ""

# メモリ
echo "[Memory]"
free -h
echo ""

# GPU情報
echo "[GPU / Tegra]"
if command -v tegrastats &>/dev/null; then
  timeout 2 tegrastats || true
else
  echo "tegrastats not found"
fi
echo ""

# ストレージ
echo "[Storage]"
df -h /
echo ""

# Python / pip
echo "[Python]"
python3 --version 2>/dev/null || echo "Python3 not found"
pip3 --version 2>/dev/null || echo "pip3 not found"
echo ""

# Docker
echo "[Docker]"
docker --version 2>/dev/null || echo "Docker not found"
echo ""

echo "=== Check Complete ==="
