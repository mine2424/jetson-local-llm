#!/bin/bash
# 推奨モデル一括ダウンロード
set -e

echo "=== Pulling recommended models ==="
echo "Storage: $(df -h / | tail -1 | awk '{print $4}') free"
echo ""

# Ollamaが起動しているか確認
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
  echo "❌ Ollama is not running. Starting..."
  ollama serve &
  sleep 3
fi

# ---- モデルリスト ----
# コメントアウトして不要なものをスキップ

echo "[1/4] Qwen2.5 7B (日本語メイン) ~4.5GB"
ollama pull qwen2.5:7b

echo ""
echo "[2/4] LFM-2.5 3B ~2.0GB"
ollama pull lfm2.5:3b 2>/dev/null || {
  echo "⚠️  LFM-2.5 not available via Ollama yet"
  echo "   → docs/lfm25_setup.md を参照して手動でGGUFを取得"
}

echo ""
echo "[3/4] Phi-3.5 Mini (コード) ~2.4GB"
ollama pull phi3.5:mini

echo ""
echo "[4/4] Gemma 2 2B (軽量バックアップ) ~1.8GB"
ollama pull gemma2:2b

echo ""
echo "=== Pull complete ==="
ollama list
