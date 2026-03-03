# LFM-2.5 セットアップガイド

## LFM-2.5 とは

Liquid AI が開発した **Liquid Foundation Model 2.5**。
Transformerではなく **SSM（State Space Model）+ Attention ハイブリッド** アーキテクチャ。

### Jetson向けメリット
- メモリ効率が高い（Transformerより省RAM）
- **125K コンテキスト** 対応（Transformerの場合同サイズでは不可能なレベル）
- 731MB (Q4_K_M) で動作する超軽量モデル

---

## Ollama上のLFM-2.5（最新調査: 2025年3月）

| モデル | Ollama タグ | サイズ | 説明 |
|-------|-----------|-------|------|
| LFM-2.5 Thinking | `lfm2.5-thinking:1.2b-q4_K_M` | 731MB | **公式・推奨** |
| LFM-2.5 Thinking Q8 | `lfm2.5-thinking:1.2b-q8_0` | 1.2GB | 高品質版 |
| LFM-2.5 日本語 | `nn-tsuzu/LFM2.5-1.2B-JP` | ~0.7GB | 日本語fine-tune |
| LFM-2.5 Instruct | `nn-tsuzu/lfm2.5-1.2b-instruct` | ~0.7GB | コミュニティ版 |

> ⚠️ **重要**: dustynv/ollama コンテナの Ollama バージョンが古いため、
> そのままでは `lfm2.5-thinking` pull が **412/500 エラー** で失敗する。
> `setup/06_setup_lfm.sh` がバイナリを自動でアップグレードしてから pull する。

---

## セットアップ方法

### 方法1: TUI メニューから（推奨）

```
./menu.sh → 1. Setup → 3. LFM-2.5 セットアップ
```

### 方法2: スクリプトを直接実行

```bash
bash setup/06_setup_lfm.sh
```

スクリプトの処理フロー:
```
[1] コンテナ内 Ollama バイナリを最新版にアップグレード
[2] lfm2.5-thinking:1.2b-q4_K_M を API pull
    ↓ 成功 → 完了
    ↓ 失敗 (互換性問題)
[3] HuggingFace から GGUF をダウンロード
    → Ollama API /api/create でインポート (lfm2.5-local)
```

### 方法3: 日本語モデルを手動で追加

```bash
# LFM-2.5 日本語 fine-tune (nn-tsuzu/LFM2.5-1.2B-JP)
curl -s -X POST http://localhost:11434/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "nn-tsuzu/LFM2.5-1.2B-JP"}' | \
  python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        if d.get('status'): print(d['status'])
    except: pass
"
```

---

## 動作確認 (API経由)

```bash
# LFM-2.5 Thinking (公式)
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "lfm2.5-thinking:1.2b-q4_K_M",
    "prompt": "こんにちは。自己紹介してください。",
    "stream": false
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"

# LFM-2.5 日本語
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nn-tsuzu/LFM2.5-1.2B-JP",
    "prompt": "機械学習とは何ですか？",
    "stream": false
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"

# インタラクティブチャット
./ollama-run.sh lfm2.5-thinking:1.2b-q4_K_M
```

---

## LFM-2.5 の特徴・使いどころ

```
✅ 使うべき場面:
  - 長いドキュメントのQ&A (125K ctx)
  - メモリを節約したい (731MB)
  - 高速推論が必要

⚠️ 苦手な場面:
  - 日本語品質: Qwen2.5 7B の方が高い
  - ツール呼び出し: 限定的サポート
```

---

## 参考リンク

- [Liquid AI公式](https://www.liquid.ai/)
- [HuggingFace: LiquidAI](https://huggingface.co/LiquidAI)
- [Ollama: lfm2.5-thinking](https://ollama.com/library/lfm2.5-thinking)
- [Ollama: nn-tsuzu/LFM2.5-1.2B-JP](https://ollama.com/nn-tsuzu/LFM2.5-1.2B-JP)
