# LFM-2.5 日本語モデル調査ノート

> 随時更新。実機確認したら結果を追記すること。

## 現状サマリ（2025年3月時点）

| モデル | 種別 | チャット用途 | 入手方法 |
|--------|------|------------|---------|
| KoichiYasuoka/lfm2.5-1.2b-japanese-ud-embeds | 形態素解析 | ❌ | HuggingFace |
| LiquidAI公式 日本語版 | 未確認 | 不明 | - |
| コミュニティfine-tune | 随時追加中 | 要確認 | HuggingFace |

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

英語ベースのLFM-2.5でも日本語入出力は可能。システムプロンプトで調整：

```bash
# Ollama Modelfile の例
cat > ~/.ollama/Modelfile_lfm25_ja <<'EOF'
FROM lfm2.5:3b

SYSTEM """
あなたは日本語を話す有能なAIアシスタントです。
ユーザーへの返答は必ず日本語で行ってください。
"""

PARAMETER num_ctx 8192
PARAMETER temperature 0.7
EOF

ollama create lfm2.5-ja -f ~/.ollama/Modelfile_lfm25_ja
ollama run lfm2.5-ja "Jetsonでローカルモデルを動かす利点を教えて"
```

## TODO（実機確認時に更新）

- [ ] LFM-2.5 1B/3B/7B の日本語応答品質を実測
- [ ] `ollama search lfm` で公式サポート確認
- [ ] HuggingFaceの日本語fine-tune版GGUFを発見したら追記
- [ ] Qwen2.5 7B との日本語品質比較ベンチマーク
