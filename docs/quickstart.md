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
# systemd 経由（インストール済みの場合）
sudo systemctl start ollama
sudo systemctl status ollama   # 確認

# systemd 未登録の場合はバックグラウンド起動
ollama serve &

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

### コマンドラインから

```bash
# 軽量モデル（まず試す場合）
ollama pull gemma2:2b        # ~1.8GB

# 日本語メイン推奨
ollama pull qwen2.5:7b       # ~4.5GB

# 省メモリ・高速
ollama pull qwen2.5:3b       # ~2.0GB

# ダウンロード済みモデルの確認
ollama list
```

> **メモリ目安**: 8GB 共有メモリのうち OS が約 2GB 使用。
> 実効使用可能は **約 5〜6GB**。7B モデル(Q4)は 1 つが限界。

---

## 3. モデルをテスト実行する

### ターミナル対話

```bash
# 対話モードで起動（Ctrl+D または /bye で終了）
ollama run qwen2.5:7b

# 1回だけ実行
ollama run qwen2.5:7b "日本語で自己紹介してください"
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
MODEL="qwen2.5:7b"

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
    "model": "qwen2.5:7b",
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
ollama ps

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
# systemd 経由
sudo systemctl stop ollama

# バックグラウンドプロセスの場合
pkill -f "ollama serve"

# 特定モデルのアンロードだけしたい場合
ollama stop qwen2.5:7b
```

---

## よくあるトラブル

| 症状 | 確認コマンド | 対処 |
|------|-------------|------|
| API が応答しない | `curl localhost:11434/api/tags` | `systemctl restart ollama` |
| モデルが遅い / 落ちる | `free -h` / `tegrastats` | より小さいモデルに切り替え |
| GPU が使われていない | `tegrastats` の `GR3D_FREQ` | `-ngl 999` オプション確認 |
| ダウンロードが止まる | — | `ollama pull` を再実行（再開される） |

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
