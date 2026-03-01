# OpenAI互換 API 使用ガイド

OllamaはOpenAI互換のREST APIを提供する。既存のOpenAIクライアントがそのまま使える。

## エンドポイント

```
http://<jetson-ip>:11434
```

| エンドポイント | 説明 |
|---------------|------|
| `GET  /api/tags` | インストール済みモデル一覧 |
| `POST /api/generate` | テキスト生成（Ollamaネイティブ） |
| `POST /v1/chat/completions` | OpenAI互換チャット |
| `POST /v1/completions` | OpenAI互換補完 |
| `GET  /v1/models` | OpenAI互換モデル一覧 |

## 外部からアクセスする設定

デフォルトは `127.0.0.1` のみ。同一LAN内の他マシンからアクセスする場合：

```bash
# /etc/systemd/system/ollama.service.d/jetson.conf を編集
Environment="OLLAMA_HOST=0.0.0.0:11434"

sudo systemctl daemon-reload && sudo systemctl restart ollama
```

## curl での動作確認

```bash
# モデル一覧
curl http://localhost:11434/api/tags | jq '.models[].name'

# チャット（OpenAI互換）
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5:7b",
    "messages": [
      {"role": "user", "content": "日本語で自己紹介してください"}
    ]
  }' | jq '.choices[0].message.content'
```

## Python (openai ライブラリ)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://192.168.x.x:11434/v1",  # JetsonのIP
    api_key="ollama",  # 任意の文字列でOK
)

response = client.chat.completions.create(
    model="qwen2.5:7b",
    messages=[
        {"role": "system", "content": "あなたは日本語で答えるAIです。"},
        {"role": "user", "content": "Jetsonでローカルモデルを動かす利点は？"},
    ],
    temperature=0.7,
    max_tokens=512,
)
print(response.choices[0].message.content)
```

## TypeScript / Node.js

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "http://192.168.x.x:11434/v1",
  apiKey: "ollama",
});

const response = await client.chat.completions.create({
  model: "qwen2.5:7b",
  messages: [{ role: "user", content: "こんにちは" }],
});

console.log(response.choices[0].message.content);
```

## ストリーミング

```python
for chunk in client.chat.completions.create(
    model="qwen2.5:7b",
    messages=[{"role": "user", "content": "長文を生成して"}],
    stream=True,
):
    print(chunk.choices[0].delta.content or "", end="", flush=True)
```

## よく使うOllamaコマンド

```bash
# 実行中モデル確認
ollama ps

# モデルをアンロード（メモリ解放）
ollama stop qwen2.5:7b

# モデル削除
ollama rm model-name

# ログ確認
journalctl -u ollama -f
```
