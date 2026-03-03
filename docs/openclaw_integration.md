# OpenClaw 統合ガイド (M6)

Jetson の llama-server を OpenClaw のローカル LLM プロバイダーとして接続する。

## 前提条件

- M1 完了（40+ t/s 確認済み）
- `scripts/llama-server-optimized.sh` で llama-server が port 8081 で起動していること
- Jetson と OpenClaw が同一ネットワーク上にあること

---

## Step 1: llama-server を起動

```bash
# Jetson 側で実行
bash scripts/llama-server-optimized.sh \
  ~/.ollama/models/blobs/<qwen3.5-4b-q4_K_M>.gguf

# 起動確認
curl http://localhost:8081/v1/models
# → {"data":[{"id":"..."}]} が返れば OK
```

---

## Step 2: ネットワーク越しのアクセス確認

```bash
# OpenClaw 側のマシンから
JETSON_IP=192.168.x.x   # 実際のJetson IPに変更

curl http://$JETSON_IP:8081/v1/models

# → 応答があれば OK
# → 応答がない場合: Jetson のファイアウォール確認
#   sudo ufw allow 8081/tcp
```

---

## Step 3: OpenClaw 設定

OpenClaw の設定ファイルにローカルプロバイダーを追加:

```yaml
# ~/.openclaw/config.yaml (または openclaw configure で設定)

providers:
  - name: local-jetson
    type: openai-compatible
    base_url: "http://192.168.x.x:8081/v1"
    api_key: "none"          # llama-server は認証不要
    default_model: "qwen3.5-4b-q4_K_M"
    timeout: 120             # 長めに設定（推論に時間がかかる）
```

または環境変数で設定:

```bash
export OPENAI_API_BASE="http://192.168.x.x:8081/v1"
export OPENAI_API_KEY="none"
```

---

## Step 4: 動作確認

```bash
# OpenAI互換 API テスト
curl http://192.168.x.x:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5-4b",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant. Reply in Japanese."},
      {"role": "user", "content": "自己紹介してください"}
    ],
    "max_tokens": 200
  }'
```

---

## 用途別モデル切り替え

| 用途 | 推奨モデル | 速度 | 品質 |
|------|-----------|------|------|
| 汎用会話・推論 | `qwen3.5:4b-q4_K_M` | 40+ t/s | ★★★★ |
| 日本語優先 | `qwen2.5:7b-instruct-q4_K_M` | 20+ t/s | ★★★★★ |
| 速度優先 | `qwen3.5:2b-q4_K_M` | 60+ t/s | ★★★ |
| 推論タスク | `deepseek-r1:1.5b-q5_K_M` | 50+ t/s | ★★★★ |

モデルを切り替えるには llama-server を再起動:

```bash
pkill -f llama-server
bash scripts/llama-server-optimized.sh /path/to/other-model.gguf
```

---

## パフォーマンス調整

OpenClaw からのリクエストが遅い場合:

```bash
# コンテキストサイズを小さくして起動 (速度優先)
"$HOME/llama.cpp/build/bin/llama-server" \
  -m model.gguf \
  -ngl 999 \
  --flash-attn \
  --ctx-size 2048 \   # 4096 → 2048 に削減
  --port 8081

# 並列リクエスト数を増やす (スループット優先)
  --parallel 2        # 同時2リクエスト (メモリ余裕があれば)
```

---

## M6 成功基準チェックリスト

- [ ] `curl http://$JETSON_IP:8081/v1/models` で応答あり
- [ ] OpenClaw から基本的な会話タスクが完結
- [ ] 単純な要約・分類タスクを **30秒以内**で完了
- [ ] 10回連続リクエストでエラーなし
- [ ] `nvidia-smi` でGPU使用率 >80% を確認（推論中）
