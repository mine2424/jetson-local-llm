# LFM-2.5 セットアップガイド

## LFM-2.5 とは

Liquid AI が開発した **Liquid Foundation Model 2.5**。
Transformerではなく **SSM（State Space Model）+ Attention ハイブリッド** アーキテクチャ。

### 特徴
- メモリ効率が高い（Transformerより省RAM）
- **125K コンテキスト** 対応
- 731MB (Q4_K_M) で動作する超軽量モデル
- **day-0 で llama.cpp / GGUF 公式サポート** ← Jetson向けに重要

---

## Jetson Orin Nano での対応方針

Ollama の `dustynv/ollama` コンテナは Ollama バージョンが古く、
LFM-2.5 は llama.cpp の比較的新しいアーキテクチャ (`lfm2` アーキ) のため
**そのままでは動かない可能性が高い。**

### セットアップフロー（自動）

```
bash setup/06_setup_lfm.sh
```

```
[1] Ollama バイナリをコンテナ内でアップグレード
[2] Ollama API pull: lfm2.5-thinking:1.2b-q4_K_M
    → 成功: Ollama (port 11434) で提供 ← 理想
    → 失敗:
[3] llama.cpp fallback (推奨)
    a. setup/05_setup_llamacpp.sh でビルド (初回のみ 10〜20分)
    b. HuggingFace GGUF を直接ダウンロード
       - Instruct: LiquidAI/LFM2.5-1.2B-Instruct-GGUF
       - 日本語:   LiquidAI/LFM2.5-1.2B-JP-GGUF  ← 推奨
    c. llama-server を port 8081 で起動 (OpenAI互換)
```

---

## Ollama上のLFM-2.5（参考情報）

| モデル | Ollama タグ | サイズ | 備考 |
|-------|-----------|-------|------|
| LFM-2.5 Thinking | `lfm2.5-thinking:1.2b-q4_K_M` | 731MB | バイナリUG後にpull |
| LFM-2.5 日本語 | `nn-tsuzu/LFM2.5-1.2B-JP` | ~0.7GB | バイナリUG後にpull |

---

## llama.cpp での利用（確実な方法）

### llama.cpp ビルド

```bash
bash setup/05_setup_llamacpp.sh
# CUDA (sm_87) 対応ビルド / 初回 10〜20 分
```

### CUI チャット

```bash
# インタラクティブチャット (-hf でHuggingFaceから自動DL)
~/llama.cpp/build/bin/llama-cli \
  -hf LiquidAI/LFM2.5-1.2B-JP-GGUF \
  -ngl 99 -c 4096

# 手動でダウンロード済みの場合
~/llama.cpp/build/bin/llama-cli \
  -m ~/.ollama/models/lfm25_gguf/LFM2.5-1.2B-JP-Q4_K_M.gguf \
  -ngl 99 -c 4096 -i
```

### OpenAI互換 APIサーバ (port 8081)

```bash
# TUIから: Service → L1. LFM-2.5 llama-server 起動
# または手動:
~/llama.cpp/build/bin/llama-server \
  -m ~/.ollama/models/lfm25_gguf/LFM2.5-1.2B-JP-Q4_K_M.gguf \
  -ngl 99 -c 4096 \
  --host 0.0.0.0 --port 8081
```

### API テスト

```bash
# 疎通確認
curl http://localhost:8081/health

# チャット (OpenAI互換)
curl -s http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "lfm2.5", "messages": [{"role": "user", "content": "こんにちは"}]}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

---

## GPU オフロードについて

```bash
# -ngl (GPU layers) の指定
-ngl 99    # 全レイヤーをGPUに (推奨: Jetson共有VRAM)
-ngl 20    # GPUが足りない場合は減らす (OOM対策)
-ngl 0     # CPU のみ (遅いが確実)
```

Jetson はCPU/GPU でメモリ共有のため、`-ngl 99` でも他プロセスとメモリ競合する可能性あり。
OOM で落ちる場合は `sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'` してから再実行。

---

## 利用可能な GGUF モデル

| HuggingFace リポジトリ | 説明 |
|----------------------|------|
| `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` | 汎用 Instruct |
| `LiquidAI/LFM2.5-1.2B-JP-GGUF` | **日本語特化** ← 推奨 |

どちらも `-hf` フラグで llama-cli から直接起動可能（自動ダウンロード）。

---

## 参考リンク

- [Liquid AI 公式 llama.cpp ドキュメント](https://docs.liquid.ai/docs/inference/llama-cpp)
- [HuggingFace: LiquidAI/LFM2.5-1.2B-Instruct](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct)
- [HuggingFace: LiquidAI/LFM2.5-1.2B-JP-GGUF](https://huggingface.co/LiquidAI/LFM2.5-1.2B-JP-GGUF)
- [Ollama: lfm2.5-thinking](https://ollama.com/library/lfm2.5-thinking)
