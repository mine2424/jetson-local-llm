# モデル一覧

> **メモリ上限**: 8GB 共有 RAM → モデルに使える実効値 ~5.2GB  
> **量子化方針**: 3B以上 = Q4_K_M 必須 / 1B台 = Q5_K_M 推奨

---

## ⭐ 推奨モデル早見表

| 用途 | モデル | サイズ | 特徴 |
|------|--------|--------|------|
| **万能メイン** | `qwen3.5:4b-q4_K_M` | 3.4GB | vision + tools + thinking, 256K ctx |
| **日本語最高** | `qwen2.5:7b-instruct-q4_K_M` | 4.7GB | 日本語トップクラス |
| **軽量バランス** | `qwen2.5:3b-instruct-q4_K_M` | 1.9GB | 日本語対応・高速 |
| **推論特化** | `deepseek-r1:1.5b-qwen-distill-q5_K_M` | 1.2GB | CoT推論・軽量 |
| **コード** | `qwen2.5-coder:7b-instruct-q4_K_M` | 4.7GB | コード最高性能 |
| **超軽量** | `smollm2:1.7b-instruct-q5_K_M` | 1.0GB | 最小・爆速 |
| **ビジョン** | `moondream2` | 1.7GB | 画像理解・超軽量 |

---

## 🟦 Qwen3.5（最新世代 — 超推奨）

vision + tools + thinking 全対応。256K ctx。Jetson 8GB で余裕動作。

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `qwen3.5:0.8b` | 0.6GB | 超軽量・vision対応 |
| `qwen3.5:2b-q4_K_M` | 1.9GB | 軽量・バランス |
| `qwen3.5:4b-q4_K_M` | 3.4GB | **★最推奨** 高性能・256K ctx |

> `/no_think` プロンプトで thinking モードを無効化 → 高速化可能

---

## 🟠 Qwen2.5（日本語最強クラス）

Alibaba 製。現時点で日本語性能がトップクラス。

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `qwen2.5:1.5b-instruct-q5_K_M` | 1.1GB | 超軽量日本語 |
| `qwen2.5:3b-instruct-q4_K_M` | 1.9GB | **★推奨** 軽量日本語 |
| `qwen2.5:7b-instruct-q4_K_M` | 4.7GB | **★推奨** 日本語最高品質 |
| `qwen2.5-coder:3b-instruct-q4_K_M` | 1.9GB | コード軽量 |
| `qwen2.5-coder:7b-instruct-q4_K_M` | 4.7GB | コード最高性能 |

---

## 🔵 Microsoft Phi

小さいが賢い。Microsoftの軽量シリーズ。

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `phi3.5:3.8b-mini-instruct-q4_K_M` | 2.2GB | 論理推論・高品質 |
| `phi4-mini:3.8b-instruct-q4_K_M` | 2.4GB | Phi最新世代 |

---

## 🟢 Google Gemma

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `gemma2:2b-instruct-q5_K_M` | 1.6GB | Gemma2 軽量・優秀 |
| `gemma3:1b-it-q5_K_M` | 0.8GB | 超軽量・最新世代 |
| `gemma3:4b-it-q4_K_M` | 2.6GB | **★推奨** バランス優秀 |

---

## 🤖 Meta Llama

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `llama3.2:1b-instruct-q5_K_M` | 0.7GB | 超軽量 |
| `llama3.2:3b-instruct-q4_K_M` | 2.0GB | 英語汎用 |

---

## 🧠 推論特化

Chain-of-thought 推論に強い。

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `deepseek-r1:1.5b-qwen-distill-q5_K_M` | 1.2GB | **★推奨** 推論・軽量 |
| `deepseek-r1:7b-qwen-distill-q4_K_M` | 4.7GB | 推論・高性能 |
| `qwq:latest` | ※要確認 | QwQ 推論特化 |

---

## 👁️ ビジョン（画像理解）

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `moondream2` | 1.7GB | **★推奨** 超軽量ビジョン |
| `qwen3.5:4b-q4_K_M` | 3.4GB | vision 内蔵・万能 |
| `llava:7b-v1.6-mistral-q4_K_M` | 4.5GB | LLaVA 高性能 |

---

## 💻 コード特化

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `qwen2.5-coder:3b-instruct-q4_K_M` | 1.9GB | コード軽量 |
| `qwen2.5-coder:7b-instruct-q4_K_M` | 4.7GB | コード最高性能 |
| `starcoder2:3b-q4_K_M` | 1.9GB | StarCoder2・コード補完 |
| `codellama:7b-instruct-q4_K_M` | 3.8GB | Meta コード特化 |

---

## 🔴 LFM-2.5（Liquid Foundation Model）

SSM + Attention ハイブリッド。125K ctx・省メモリ。

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `lfm2.5-thinking:1.2b-q4_K_M` | 731MB | **Ollama公式** thinking対応 |
| `lfm2.5-thinking:1.2b-q8_0` | 1.2GB | 高品質版 |
| `nn-tsuzu/LFM2.5-1.2B-JP` | 0.7GB | **日本語 fine-tune** |

> ⚠️ dustynv/ollama の古いバイナリでは pull 失敗する場合あり → `bash setup/06_setup_lfm.sh`

---

## ⚡ 超軽量 (<1.5GB)

速度最優先・リソース節約。

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `smollm2:360m-instruct-q8_0` | 0.4GB | **最軽量** HuggingFace |
| `smollm2:1.7b-instruct-q5_K_M` | 1.0GB | **★推奨** 小さいが賢い |
| `qwen3.5:0.8b` | 0.6GB | vision対応 |
| `llama3.2:1b-instruct-q5_K_M` | 0.7GB | Meta 超軽量 |
| `gemma3:1b-it-q5_K_M` | 0.8GB | Google 超軽量 |

---

## 🌐 多言語・日本語特化

| Ollama タグ | サイズ | 特徴 |
|-----------|--------|------|
| `qwen2.5:7b-instruct-q4_K_M` | 4.7GB | 日本語最高性能 |
| `nn-tsuzu/LFM2.5-1.2B-JP` | 0.7GB | 日本語 fine-tune |
| `granite3.1-moe:3b-instruct-q4_K_M` | 2.1GB | IBM MoE・多言語 |

---

## ❌ 8GB Jetson では動かないもの

| モデル | サイズ | 理由 |
|--------|--------|------|
| `llama3.1:8b-q4_K_M` | 5.2GB | OOM リスク高 |
| `qwen2.5:14b` | 9.0GB | VRAM超過 |
| `gemma3:12b-it-q4_K_M` | 7.5GB | ギリギリ不可 |
| `phi4:14b` | 8.9GB | VRAM超過 |
| `deepseek-r1:14b` | 8.9GB | VRAM超過 |

---

## 📊 ベンチマーク実測値

> `./menu.sh → 4. Benchmark` または `bash benchmark/run_bench.sh` で計測

| モデル | tokens/sec | 計測日 | 備考 |
|--------|-----------|--------|------|
| - | - | 未計測 | - |

---

## メモリ使用量の目安

```
8GB RAM 内訳:
  OS + システム:     ~1.5GB
  Ollama プロセス:   ~0.3GB
  GPU確保(NvMap):    ~1.0GB
  ─────────────────────────
  モデルに使える:    ~5.2GB

安全に動くモデルサイズ: ~4.7GB 以下
```
