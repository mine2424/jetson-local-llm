# モデル一覧

> **前提**: 8GB共有メモリ / 実効使用可能 ~5.5GB
>
> **量子化方針**:
> - 3B以上は **Q4_K_M 必須**（品質・サイズのベストバランス）
> - 1B台は **Q5_K_M 推奨**（小さいので品質を上げる余裕あり）
> - lfm2.5-thinking は 1.2B だが Q4_K_M でも十分な品質

---

## 🔴 LFM-2.5（Liquid Foundation Model 2.5）

SSM + Attention ハイブリッド。Jetson向けメリット:
- メモリ効率が高い（Transformerより省RAM）
- 125K コンテキスト対応

| モデル名 | Ollama タグ | サイズ | コンテキスト | 備考 |
|---------|-----------|-------|------------|------|
| LFM-2.5 Thinking | `lfm2.5-thinking:1.2b-q4_K_M` | 731MB | 125K | **Ollama公式 ✅** |
| LFM-2.5 Thinking (高品質) | `lfm2.5-thinking:1.2b-q8_0` | 1.2GB | 125K | Q8精度優先 |
| LFM-2.5 日本語 | `nn-tsuzu/LFM2.5-1.2B-JP` | ~0.7GB | - | **日本語fine-tune ✅** |
| LFM-2.5 Instruct | `nn-tsuzu/lfm2.5-1.2b-instruct` | ~0.7GB | - | コミュニティ版 |

> ⚠️ dustynv/ollama コンテナの Ollama バージョンが古い場合は pull が失敗する。
> `bash setup/06_setup_lfm.sh` でバイナリを自動アップグレードして対応。

---

## 🟠 Qwen2.5（日本語最強クラス）

Alibaba製。現時点で日本語性能がトップクラス。

| サイズ | Ollama タグ | サイズ(disk) | 特徴 |
|-------|-----------|------------|------|
| 0.5B | `qwen2.5:0.5b-instruct-q5_K_M` | ~400MB | 超軽量テスト用 |
| 1.5B | `qwen2.5:1.5b-instruct-q5_K_M` | ~1.1GB | 軽量日本語 |
| 3B | `qwen2.5:3b-instruct-q4_K_M` | 1.9GB | **推奨: 軽量・高品質** |
| 7B | `qwen2.5:7b-instruct-q4_K_M` | 4.7GB | **推奨: 日本語最高性能** |

---

## 🟠 Qwen2.5-Coder（コード特化）

| サイズ | Ollama タグ | サイズ(disk) | 特徴 |
|-------|-----------|------------|------|
| 3B | `qwen2.5-coder:3b-instruct-q4_K_M` | 1.9GB | **推奨: コード軽量** |
| 7B | `qwen2.5-coder:7b-instruct-q4_K_M` | 4.7GB | コード最高性能 |

---

## 🟡 Qwen3（最新世代・2025年）

thinking mode対応。`/no_think` で高速モードに切替可能。

| サイズ | Ollama タグ | サイズ(disk) | 特徴 |
|-------|-----------|------------|------|
| 1.7B | `qwen3:1.7b-q5_K_M` | ~1.3GB | 推論機能付き軽量 |
| 4B | `qwen3:4b-q4_K_M` | ~2.6GB | **推奨: 最新・高性能** |
| 8B | `qwen3:8b-q4_K_M` | ~5.2GB | ギリギリ動作 ⚠️ |

---

## 🟢 Gemma 3（Google）

| サイズ | Ollama タグ | サイズ(disk) | 特徴 |
|-------|-----------|------------|------|
| 1B | `gemma3:1b-it-q5_K_M` | ~0.8GB | 超軽量・優秀 |
| 4B | `gemma3:4b-it-q4_K_M` | ~2.6GB | **推奨: バランス優秀** |

---

## 🔵 Llama 3.2（Meta）

| サイズ | Ollama タグ | サイズ(disk) | 特徴 |
|-------|-----------|------------|------|
| 1B | `llama3.2:1b-instruct-q5_K_M` | ~0.7GB | 超軽量 |
| 3B | `llama3.2:3b-instruct-q4_K_M` | 2.0GB | 英語汎用 |

---

## 🟣 DeepSeek-R1（推論特化）

Chain-of-thought推論に強い。

| サイズ | Ollama タグ | サイズ(disk) | 特徴 |
|-------|-----------|------------|------|
| 1.5B | `deepseek-r1:1.5b-qwen-distill-q5_K_M` | ~1.2GB | 推論軽量 |
| 7B | `deepseek-r1:7b-qwen-distill-q4_K_M` | 4.7GB | 推論高性能 |

---

## ⚪ Mistral（汎用）

| サイズ | Ollama タグ | サイズ(disk) | 特徴 |
|-------|-----------|------------|------|
| 7B | `mistral:7b-instruct-v0.3-q4_K_M` | 4.1GB | 汎用・安定 |

---

## ❌ 8GB Jetson では動かないもの

| モデル | サイズ | 理由 |
|-------|--------|------|
| qwen2.5:14b | 9.0GB | VRAM超過 |
| phi4:14b | ~8.9GB | VRAM超過 |
| llama3.1:8b-q4_K_M | ~5.2GB | MemFree不足でOOMリスク |

---

## ⚠️ メモリ注意事項

```
8GB RAM の内訳（目安）:
  OS + システム:   ~1.5GB
  Ollama プロセス: ~0.3GB
  GPU メモリ確保:  ~1.0GB (NvMap用 MemFree)
  ─────────────────────────
  モデルに使える:  ~5.2GB
```

- `ollama ps` でロード中モデルのVRAM使用量を確認
- 複数モデルの同時ロードは禁止 (`OLLAMA_MAX_LOADED_MODELS=1` 設定済み)
- OOM時は `sudo docker restart ollama` + `drop_caches` が有効

---

## 📊 ベンチマーク実測値

> `./menu.sh → 4. Benchmark` または `bash benchmark/run_bench.sh` で計測

| モデル | tokens/sec | eval_ms | 計測日 |
|--------|-----------|---------|--------|
| - | - | - | 未計測 |
