# クイックスタートガイド

## 1. セットアップ (初回のみ)

```bash
git clone https://github.com/mine2424/jetson-local-llm
cd jetson-local-llm
bash install.sh
```

セットアップ完了後、全操作は TUI メニューから行う:

```bash
./menu.sh
```

> 起動するだけで MAXN 電源モード + GPU クロック固定が自動適用される。

---

## 2. 基本操作フロー

```
./menu.sh
│
├─ 1. Service → 2. 起動     ← まずOllamaを起動
│
├─ 1. Service → 5. チャット ← モデル選んでそのまま対話
│
└─ 1. Service → 1. ステータス ← GPU使用率・メモリ確認
```

---

## 3. よく使うコマンド (メニュー外)

```bash
# GPU が使われているか確認
watch -n 1 nvidia-smi

# モデルを直接 pull (Ollama API)
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "qwen3.5:4b-q4_K_M"}'

# API でチャット (curl)
curl http://localhost:11434/api/generate \
  -d '{"model":"qwen3.5:4b-q4_K_M","prompt":"こんにちは","stream":false}'

# GPU が使われていない場合の修正
bash scripts/fix_ollama_gpu.sh

# 日本語品質評価 (M2)
bash eval/japanese_eval.sh

# 性能診断
bash scripts/diagnose.sh
```

---

## 4. モデル選び

| 目的 | 推奨 | サイズ |
|------|------|--------|
| まず試す | `qwen3.5:4b-q4_K_M` | 3.4GB |
| 日本語校正 | `qwen2.5:7b-instruct-q4_K_M` | 4.7GB |
| 爆速・軽量 | `smollm2:1.7b-instruct-q5_K_M` | 1.0GB |
| 推論タスク | `deepseek-r1:1.5b-qwen-distill-q5_K_M` | 1.2GB |
| 画像入力 | `moondream2` | 1.7GB |
| コード生成 | `qwen2.5-coder:7b-instruct-q4_K_M` | 4.7GB |

---

## 5. GPU 動作確認

Ollama 起動後にモデルをロードして `nvidia-smi` を見る:

```bash
# GPU メモリ使用量が増えれば GPU 動作中
nvidia-smi

# 期待する出力例:
# | NVIDIA Tegra ...
# +------------------------------------------+
# | GPU-Util: 90%   MEM: 4200MiB / 7982MiB  |
```

**GPU メモリが増えない場合:**

```bash
./menu.sh → Setup → GPU 診断・修正
```

---

## 6. トラブルシューティング

| 症状 | 対処 |
|------|------|
| 7 t/s のまま | GPU 未使用 → Setup → GPU 診断・修正 |
| OOM クラッシュ | `sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'` |
| API 応答なし | `sudo docker restart ollama` |
| モデル pull 失敗 | `sudo docker logs ollama` でエラー確認 |
| LFM-2.5 pull 失敗 | `bash setup/06_setup_lfm.sh` でバイナリ更新 |
