# LFM-2.5 日本語モデル調査ノート

> 随時更新。実機確認したら結果を追記すること。

## 現状サマリ（2025年3月時点）

| モデル | 種別 | チャット用途 | 入手方法 |
|--------|------|------------|---------|
| **nn-tsuzu/LFM2.5-1.2B-JP** | 日本語チャット | ✅ | **Ollama上に存在** |
| nn-tsuzu/lfm2.5-1.2b-instruct | 汎用Instruct | ✅ | Ollama上に存在 |
| KoichiYasuoka/lfm2.5-1.2b-japanese-ud-embeds | 形態素解析 | ❌ | HuggingFace |

## nn-tsuzu/LFM2.5-1.2B-JP ← 日本語チャット推奨

**Ollama上に公開されている日本語fine-tune版** ✅

```bash
# API経由でpull
curl -s -X POST http://localhost:11434/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "nn-tsuzu/LFM2.5-1.2B-JP"}' | \
  python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        if d.get('status'): print(d['status'])
    except: pass
"

# 動作確認
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model": "nn-tsuzu/LFM2.5-1.2B-JP", "prompt": "機械学習とは何ですか？", "stream": false}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"

# インタラクティブ
./ollama-run.sh nn-tsuzu/LFM2.5-1.2B-JP
```

> ⚠️ dustynv/ollama の古いバージョンでは pull が失敗する。
> `bash setup/06_setup_lfm.sh` でバイナリをアップグレードしてから実行すること。

## KoichiYasuoka/lfm2.5-1.2b-japanese-ud-embeds

- **用途**: Universal Dependencies (UD) 形式での日本語係り受け解析・形態素解析
- **チャットには使えない** → llama.cppやOllamaでの会話用途ではなくPyTorchで使うNLPモデル
- 参考: <https://huggingface.co/KoichiYasuoka/lfm2.5-1.2b-japanese-ud-embeds>

## 日本語チャット用 LFM-2.5 を探す手順

```bash
# HuggingFaceで日本語GGUFを検索
pip3 install huggingface_hub

python3 << 'EOF'
from huggingface_hub import HfApi
api = HfApi()

# LFM-2.5 GGUF を検索
results = api.list_models(
    search="lfm-2.5",
    library="gguf",
    sort="lastModified",
    direction=-1,
    limit=20
)
for r in results:
    print(r.id, r.lastModified)
EOF
```

## 日本語性能が高い代替モデル（現実的な選択肢）

LFM-2.5の日本語fine-tuneが揃うまでの代替：

| モデル | Ollama ID | 日本語評価 | メモリ |
|--------|-----------|-----------|--------|
| Qwen2.5 7B | `qwen2.5:7b` | ◎ 最高クラス | ~4.5GB |
| Qwen2.5 3B | `qwen2.5:3b` | ○ | ~2.0GB |
| Gemma 2 2B | `gemma2:2b` | △ | ~1.8GB |

## LFM-2.5 + 日本語プロンプト戦略

英語ベースのLFM-2.5でも日本語入出力は可能。
Modelfileでシステムプロンプトを設定し、**Ollama API `/api/create`** でインポートする。

```bash
# 日本語システムプロンプト付きモデルを作成 (API経由)
# ベースモデルに lfm2.5-local (setup/06_setup_lfm.sh でインポート済み) を使う

MODELFILE='FROM lfm2.5-local

SYSTEM """
あなたは日本語を話す有能なAIアシスタントです。
ユーザーへの返答は必ず日本語で行ってください。
"""

PARAMETER num_ctx 4096
PARAMETER temperature 0.7'

# API /api/create でモデル登録
curl -s -X POST http://localhost:11434/api/create \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "
import json
modelfile = '''$MODELFILE'''
print(json.dumps({'name': 'lfm2.5-ja', 'modelfile': modelfile, 'stream': False}))
")" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','?'))"

# 動作確認 (API)
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model": "lfm2.5-ja", "prompt": "Jetsonでローカルモデルを動かす利点を教えて", "stream": false}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"

# インタラクティブチャット
./ollama-run.sh lfm2.5-ja
```

## TODO（実機確認時に更新）

- [ ] LFM-2.5 1.2B の日本語応答品質を実測
- [ ] HuggingFaceの日本語fine-tune版GGUFを発見したら追記
- [ ] Qwen2.5 7B との日本語品質比較ベンチマーク
