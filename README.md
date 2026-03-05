# Jetson Local LLM

Jetson Orin Nano Super でローカル LLM を動かす環境。
TUI メニュー（`./menu.sh`）から全操作が可能。

## ハードウェア要件

| 項目 | 仕様 |
|------|------|
| ボード | Jetson Orin Nano Super |
| RAM | 8GB (CPU/GPU 共有) |
| ストレージ | 256GB NVMe SSD 推奨 |
| JetPack | 6.x |

## クイックスタート

```bash
# 1. リポジトリを取得
git clone https://github.com/mine2424/jetson-local-llm
cd jetson-local-llm

# 2. 初回セットアップ
bash install.sh

# 3. 以降は TUI メニューから操作
./menu.sh
```

> `./menu.sh` を起動するだけで MAXN 電源モード + GPU クロック固定が自動適用される。

## メニュー構成

```
./menu.sh
├── 1. 🚀 Service   — 起動・停止・チャット・ログ
├── 2. 📦 Models    — モデル管理 (pull / 削除)
├── 3. ⚙️  Setup     — 初回セットアップ・GPU修正
└── 4. 📊 Benchmark — 性能計測
```

### Service メニュー

| 項目 | 内容 |
|------|------|
| ステータス | GPU使用率・VRAM・モデル一覧・電源モード確認 |
| 起動 | Ollama Docker コンテナを GPU 最適化込みで起動 |
| 停止 | Ollama を停止 |
| 再起動 | GPU メモリを解放してから再起動 |
| チャット | モデルを選んでそのまま対話 |
| ログ | Ollama / llama-server のログを表示 |

### Setup メニュー

| 項目 | 内容 |
|------|------|
| 初回セットアップ | jetson-containers + Ollama + モデル pull |
| GPU 診断・修正 | コンテナの GPU 環境変数を確認・修正・動作検証 |
| llama.cpp ビルド | CUDA sm_87 対応でソースビルド |

## アーキテクチャ

```
Jetson Orin Nano Super
│
├── Ollama (jetson-containers Docker)    ← メイン推論エンジン
│   ├── イメージ: autotag ollama (JetPack に自動対応)
│   ├── API: http://localhost:11434
│   ├── GGML_CUDA_NO_VMM=1              ← Jetson 統合メモリ必須
│   ├── OLLAMA_NUM_GPU=999              ← 全レイヤー GPU オフロード
│   └── OLLAMA_FLASH_ATTENTION=1
│
└── llama-server (llama.cpp ネイティブ) ← GGUF モデル用 fallback
    ├── API: http://localhost:8081 (OpenAI 互換)
    ├── GGML_CUDA_NO_VMM=1
    └── -ngl 999 --flash-attn
```

## 推奨モデル

| モデル | サイズ | 用途 | 備考 |
|--------|--------|------|------|
| `qwen3.5:4b-q4_K_M` | 3.4GB | **メイン推奨** | vision + tools + thinking |
| `qwen2.5:7b-instruct-q4_K_M` | 4.7GB | 日本語品質重視 | 最高品質・低速 |
| `qwen2.5:3b-instruct-q4_K_M` | 1.9GB | 軽量・速度重視 | 日本語対応 |
| `deepseek-r1:1.5b-qwen-distill-q5_K_M` | 1.2GB | 推論特化 | CoT 推論 |

> 3B 以上は **Q4_K_M 必須**（8GB メモリ制約）

## Jetson GPU 最適化

Jetson 特有の設定が必要:

```bash
# Jetson は CUDA VMM 非対応 → これなしで GPU が使われない
export GGML_CUDA_NO_VMM=1

# 全レイヤーを GPU にオフロード
export OLLAMA_NUM_GPU=999    # Ollama
-ngl 999                     # llama-server

# 電源モード最大化
sudo nvpmodel -m 0           # MAXN モード
sudo jetson_clocks           # クロック固定
```

GPU が使われているかの確認:

```bash
# 推論中に別ターミナルで
nvidia-smi
watch -n 1 nvidia-smi
```

## 速度目安

| 状態 | 速度 | 原因 |
|------|------|------|
| CPU 推論 | ~7 t/s | `-ngl 0` または GGML_CUDA_NO_VMM 未設定 |
| GPU オフロード | 40〜60 t/s | `-ngl 999` + MAXN 電源 |
| 投機的デコーディング | 80〜120 t/s | `scripts/speculative.sh` |

## マイルストーン

→ [MILESTONES.md](MILESTONES.md) を参照

| # | 目標 | 状態 |
|---|------|------|
| M1 | 推論性能確立 (40+ t/s) | 🔧 進行中 |
| M2 | 日本語品質確立 | ⏳ |
| M3 | 構造化出力 / レポート生成 | ⏳ |
| M4 | Tool Calling + MCP | ⏳ |
| M5 | テスト項目自動生成 | ⏳ |
| M6 | OpenClaw 統合 | ⏳ |

## スクリプト一覧

| スクリプト | 内容 |
|-----------|------|
| `install.sh` | ワンショット初回セットアップ |
| `menu.sh` | TUI メインメニュー |
| `scripts/fix_ollama_gpu.sh` | Ollama コンテナの GPU 修正・検証 |
| `scripts/llama-server-optimized.sh` | llama-server 最適化起動 |
| `scripts/speculative.sh` | 投機的デコーディング (2〜3x 高速) |
| `scripts/diagnose.sh` | GPU / 電源 / CUDA 一括診断 |
| `eval/japanese_eval.sh` | 日本語品質評価 (M2) |
| `setup/09_optimize_perf.sh` | 電源モード・クロック最適化 |

## トラブルシューティング

**GPU が使われない (7 t/s のまま):**
```bash
./menu.sh → Setup → GPU 診断・修正
# または
bash scripts/fix_ollama_gpu.sh
```

**モデルのダウンロードに失敗:**
```bash
# コンテナのログを確認
sudo docker logs ollama
```

**OOM (メモリ不足) クラッシュ:**
```bash
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
sudo docker restart ollama
```
