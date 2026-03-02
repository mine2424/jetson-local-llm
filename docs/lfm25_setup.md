# LFM-2.5 セットアップガイド

## LFM-2.5 とは

Liquid AI が開発した **Liquid Foundation Model 2.5**。
Transformerではなく **SSM（State Space Model）+ Attention ハイブリッド** アーキテクチャ。

### Jetson向けメリット
- メモリ効率が高い（Transformerより省RAM）
- 長いコンテキストでもメモリ線形増加（Transformer = 二乗）
- 8GB共有メモリのJetsonに向いている

## Ollama での利用（公式サポートモデル）

```bash
# Ollama 公式対応モデルをAPI経由でダウンロード
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "lfm2.5-thinking"}'

# 動作確認 (API)
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "lfm2.5-thinking",
    "prompt": "こんにちは",
    "stream": false
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"
```

> ⚠️ Ollama の公式サポート状況は変わる可能性あり。
> `GET http://localhost:11434/api/tags` で利用可能なモデルを確認。

## HuggingFace GGUF からセットアップ（自動スクリプト）

TUI メニューから実行:

```
4. Setup → 3. LFM-2.5 セットアップ
```

または:

```bash
bash setup/06_setup_lfm.sh
```

スクリプトが行う処理:
1. `huggingface_hub` インストール確認
2. `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` (Q4_K_M ~0.7GB) をダウンロード
   - 保存先: `~/.ollama/models/lfm25_gguf/` (コンテナマウントパス内)
3. コンテナ内 Ollama バイナリを最新版にアップグレード
4. Ollama API `/api/create` でモデルをインポート

## 手動セットアップ

OllamaにないモデルはGGUF変換版を直接インポートできる。

```bash
# GGUF を ~/.ollama/models/ 以下に配置 (コンテナマウントパス)
mkdir -p ~/.ollama/models/imports
cd ~/.ollama/models/imports

# HuggingFaceからGGUF取得
pip3 install huggingface_hub
python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(
  repo_id='LiquidAI/LFM2.5-1.2B-Instruct-GGUF',
  filename='LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
  local_dir='.'
)
"

# API /api/create でインポート
# コンテナ内パス: /data/models/ollama/models/imports/LFM2.5-1.2B-Instruct-Q4_K_M.gguf
python3 - <<'PYEOF'
import json, subprocess

modelfile = """FROM /data/models/ollama/models/imports/LFM2.5-1.2B-Instruct-Q4_K_M.gguf

SYSTEM "You are a helpful assistant."

TEMPLATE "<|im_start|>system\n{{ .System }}<|im_end|>\n<|im_start|>user\n{{ .Prompt }}<|im_end|>\n<|im_start|>assistant\n"

PARAMETER stop "<|im_end|>"
PARAMETER num_ctx 4096
PARAMETER temperature 0.2
"""

payload = json.dumps({
    "name": "lfm2.5-1.2b-local",
    "modelfile": modelfile,
    "stream": False
})

result = subprocess.run(
    ["curl", "-s", "-X", "POST", "http://localhost:11434/api/create",
     "-H", "Content-Type: application/json", "-d", payload],
    capture_output=True, text=True
)
print(result.stdout)
PYEOF

# 動作確認 (API)
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "lfm2.5-1.2b-local",
    "prompt": "こんにちは。自己紹介してください。",
    "stream": false
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"
```

## 日本語モデル

### KoichiYasuoka/lfm2.5-1.2b-japanese-ud-embeds
- 用途: 日本語形態素解析・係り受け解析（UD形式）
- チャット用途ではなくNLPタスク向け

### 汎用日本語チャット
現時点ではLFM-2.5の日本語チャット特化版は未確認。
**代替**: Qwen2.5 7B（日本語最強クラス）を併用推奨。

## 参考リンク

- [Liquid AI公式](https://www.liquid.ai/)
- [HuggingFace: LiquidAI](https://huggingface.co/LiquidAI)
- [GGUF変換版を探す](https://huggingface.co/models?search=lfm-2.5&library=gguf)
