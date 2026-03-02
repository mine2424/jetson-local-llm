# OpenAI互換 API 使用ガイド

OllamaはOpenAI互換のREST APIを提供する。既存のOpenAIクライアントがそのまま使える。

## エンドポイント

```
http://localhost:11434
```

| エンドポイント | 説明 |
|---------------|------|
| `GET  /api/tags` | インストール済みモデル一覧 |
| `GET  /api/ps` | ロード中のモデル一覧 |
| `POST /api/pull` | モデルのダウンロード |
| `DELETE /api/delete` | モデルの削除 |
| `POST /api/generate` | テキスト生成（Ollamaネイティブ） |
| `POST /api/create` | GGUFからモデルをインポート |
| `POST /v1/chat/completions` | OpenAI互換チャット |
| `POST /v1/completions` | OpenAI互換補完 |
| `GET  /v1/models` | OpenAI互換モデル一覧 |

## 外部からアクセスする設定

デフォルトは `127.0.0.1` のみ。同一LAN内の他マシンからアクセスする場合、
コンテナの `-p` フラグを変更して作り直す:

```bash
sudo docker stop ollama && sudo docker rm ollama
IMAGE=$(autotag ollama)

sudo docker run -d \
  --name ollama \
  --runtime nvidia \
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e OLLAMA_FLASH_ATTENTION=1 \
  -e OLLAMA_MAX_LOADED_MODELS=1 \
  -e OLLAMA_KEEP_ALIVE=5m \
  -e OLLAMA_NUM_CTX=2048 \
  -v "$HOME/.ollama/models:/data/models/ollama/models" \
  -p 11434:11434 \   # 0.0.0.0 でバインド
  --restart unless-stopped \
  "$IMAGE" \
  /bin/sh -c '/start_ollama; tail -f /data/logs/ollama.log'
```

別マシンからは `http://<jetson-ip>:11434` でアクセスできる。

## curl での動作確認

```bash
# モデル一覧
curl http://localhost:11434/api/tags | python3 -m json.tool

# チャット（OpenAI互換）
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5:7b",
    "messages": [
      {"role": "user", "content": "日本語で自己紹介してください"}
    ]
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"

# ネイティブ生成API
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5:7b",
    "prompt": "日本語で自己紹介してください",
    "stream": false
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"
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

## モデル管理 (API)

```bash
# モデルをダウンロード
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "qwen2.5:3b"}'

# ロード中モデルを確認
curl -s http://localhost:11434/api/ps | python3 -m json.tool

# モデルをアンロード (keep_alive=0)
curl -s -X POST http://localhost:11434/api/generate \
  -d '{"model": "qwen2.5:7b", "keep_alive": 0}'

# モデルを削除
curl -X DELETE http://localhost:11434/api/delete \
  -d '{"name": "model-name"}'

# ログ確認
sudo docker logs -f ollama
```
