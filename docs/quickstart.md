# Ollama 起動 & ローカル LLM テスト クイックスタート

Jetson Orin Nano Super (8GB) でローカル LLM を動かすまでの最短手順。

---

## 1. Ollama を起動する

### TUI メニューから起動（推奨）

```bash
./menu.sh
```

`3. Service → 2. Ollama 起動` を選択。

### コマンドラインから起動

```bash
# ページキャッシュを解放してGPUメモリを確保
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'

# Docker コンテナを起動
sudo docker start ollama

# API の応答確認
curl http://localhost:11434/api/tags
```

> **ポート**: Ollama は `localhost:11434` でリッスンします。

---

## 2. モデルをダウンロードする

### TUI メニューから

```
2. Models → 2. 推奨モデルをpull (選択式)
```

スペースキーで選択し、Enter で確定。

### API から

```bash
# 軽量モデル（まず試す場合）
curl -X POST http://localhost:11434/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "gemma2:2b"}'

# 日本語メイン推奨
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "qwen2.5:7b"}'

# 省メモリ・高速
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "qwen2.5:3b"}'

# ダウンロード済みモデルの確認
curl -s http://localhost:11434/api/tags | python3 -m json.tool
```

> **メモリ目安**: 8GB 共有メモリのうち OS が約 2GB 使用。
> 実効使用可能は **約 5〜6GB**。7B モデル(Q4)は 1 つが限界。

---

## 3. モデルをテスト実行する

### ollama run でインタラクティブチャット（最も簡単）

```bash
# ラッパースクリプトを使う
./ollama-run.sh qwen2.5:3b

# または直接 docker exec で
sudo docker exec -it ollama ollama run qwen2.5:3b

# 終了: /bye または Ctrl+D
```

### API で直接実行

```bash
# 1回だけ実行 (stream: false でレスポンス一括取得)
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5:3b",
    "prompt": "日本語で自己紹介してください",
    "stream": false
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"
```

### TUI メニューから

```
2. Models → 7. モデルをテスト実行
```

モデルを選択してプロンプトを入力するとレスポンスを表示。

---

## 4. API で動作確認する

### OpenAI 互換 REST API（v1）

```bash
MODEL="qwen2.5:3b"

curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"$MODEL"'",
    "messages": [
      {"role": "user", "content": "Hello! Reply in one sentence."}
    ]
  }'
```

### Ollama ネイティブ API

```bash
curl http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5:3b",
    "prompt": "日本語で自己紹介してください",
    "stream": false
  }'
```

### TUI メニューから

```
3. Service → 8. API 疎通テスト
```

モデルを選択すると `curl` で疎通確認し、レスポンスを表示。

---

## 5. リソースを確認する

```bash
# メモリ使用量
free -h

# ロード中のモデル一覧（メモリ占有を確認）
curl -s http://localhost:11434/api/ps | python3 -m json.tool

# GPU / CPU / RAM リアルタイム監視
tegrastats --interval 1000

# TUI からも確認可能
# → 3. Service → 9. Jetson リソースモニタ
```

### tegrastats の読み方

```
RAM 3500/7993MB (lfb 1x2MB)   ← 使用中 / 合計
GR3D_FREQ 98%                 ← GPU使用率 (高いほどGPUで推論中)
CPU [45%@1510,...]            ← CPU使用率 @ 周波数(MHz)
```

---

## 6. Ollama を停止する

```bash
# コンテナを停止
sudo docker stop ollama

# ロード中モデルだけアンロード (keep_alive=0)
curl -s -X POST http://localhost:11434/api/generate \
  -d '{"model": "qwen2.5:3b", "keep_alive": 0}'
```

---

## よくあるトラブル

| 症状 | 確認コマンド | 対処 |
|------|-------------|------|
| API が応答しない | `curl localhost:11434/api/tags` | `sudo docker start ollama` |
| モデルが遅い / 落ちる | `free -h` / `tegrastats` | より小さいモデルに切り替え |
| GPU が使われていない | `tegrastats` の `GR3D_FREQ` | drop_caches → docker restart ollama |
| ダウンロードが止まる | — | pull リクエストを再送（再開される） |

詳細 → `docs/troubleshooting.md`

---

## 推奨モデル早見表

| 優先 | モデル | サイズ | 用途 |
|------|--------|--------|------|
| ★ | `qwen2.5:7b` | ~4.5GB | 日本語メイン |
| ★ | `qwen2.5:3b` | ~2.0GB | 軽量日本語 |
| — | `gemma2:2b` | ~1.8GB | 動作確認・超軽量 |
| — | `phi3.5:mini` | ~2.4GB | コード生成 |

全一覧 → `models/model_list.md`
