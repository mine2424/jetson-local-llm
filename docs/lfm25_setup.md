# LFM-2.5 セットアップガイド

## LFM-2.5 とは

Liquid AI が開発した **Liquid Foundation Model 2.5**。  
Transformerではなく **SSM（State Space Model）+ Attention ハイブリッド** アーキテクチャ。

### Jetson向けメリット
- メモリ効率が高い（Transformerより省RAM）
- 長いコンテキストでもメモリ線形増加（Transformer = 二乗）
- 8GB共有メモリのJetsonに向いている

## Ollama での利用

```bash
# LFM-2.5がOllamaに追加された場合
ollama pull lfm2.5:1b
ollama pull lfm2.5:3b
ollama pull lfm2.5:7b

# 動作確認
ollama run lfm2.5:3b "こんにちは"
```

> ⚠️ 2025年時点でOllamaの公式サポート状況は変わる可能性あり。
> `ollama search lfm` で最新を確認。

## HuggingFace GGUF から手動セットアップ

OllamaにないモデルはGGUF変換版を直接使う。

```bash
# GGUF ダウンロード (例: bartowski の変換版)
mkdir -p ~/.ollama/models/lfm25
cd ~/.ollama/models/lfm25

# HuggingFaceからGGUF取得
pip3 install huggingface_hub
python3 -c "
from huggingface_hub import hf_hub_download
# bartowski/LFM-2.5-7B-GGUF などを探す
hf_hub_download(
  repo_id='bartowski/LFM-2.5-3B-GGUF',
  filename='LFM-2.5-3B-Q4_K_M.gguf',
  local_dir='.'
)
"

# Ollamaでimport
cat > Modelfile <<'EOF'
FROM ./LFM-2.5-3B-Q4_K_M.gguf

TEMPLATE """<|im_start|>system
{{ .System }}<|im_end|>
<|im_start|>user
{{ .Prompt }}<|im_end|>
<|im_start|>assistant
"""

PARAMETER stop "<|im_end|>"
PARAMETER num_ctx 8192
EOF

ollama create lfm2.5-3b-local -f Modelfile
ollama run lfm2.5-3b-local "こんにちは"
```

## 日本語モデル

### KoichiYasuoka/lfm2.5-1.2b-japanese-ud-embeds
- 用途: 日本語形態素解析・係り受け解析（UD形式）
- チャット用途ではなくNLPタスク向け
- llama.cpp では動作しない可能性あり（SafeTensors形式）

### 汎用日本語チャット
現時点ではLFM-2.5の日本語チャット特化版は未確認。  
**代替**: Qwen2.5 7B（日本語最強クラス）を併用推奨。

## llama.cpp での実行

```bash
# GPU全レイヤーをVRAMに乗せる (-ngl 999)
llama-cli \
  -m ~/.ollama/models/lfm25/LFM-2.5-3B-Q4_K_M.gguf \
  -p "こんにちは。自己紹介をしてください。" \
  -ngl 999 \
  -c 8192 \
  -n 512
```

## 参考リンク

- [Liquid AI公式](https://www.liquid.ai/)
- [HuggingFace: LiquidAI](https://huggingface.co/LiquidAI)
- [GGUF変換版を探す](https://huggingface.co/models?search=lfm-2.5&library=gguf)
