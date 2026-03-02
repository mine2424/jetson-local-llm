# モデル一覧

> 8GB共有メモリ前提。実効使用可能RAMは約5〜6GB。
> モデルの操作は Ollama API 経由。

## ✅ 推奨モデル

### LFM-2.5（Liquid Foundation Model）

SSMベースのハイブリッドアーキテクチャ。Transformerより省メモリ・長コンテキスト得意。

| モデル | Ollama ID | サイズ(Q4) | tokens/sec(推定) | 備考 |
|--------|-----------|-----------|-----------------|------|
| LFM-2.5 Thinking 1.2B | `lfm2.5-thinking` | ~0.7GB | ★★★★★ | Ollama公式・推論特化 |
| LFM-2.5 1.2B Instruct | `hadad/LFM2.5-1.2B:Q4_K_M` | ~0.7GB | ★★★★★ | 軽量汎用 |

**GGUF から手動インポート:**
- `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` → `setup/06_setup_lfm.sh` で自動インポート
- 日本語チャット特化版は未確認 → `docs/lfm25_japanese.md`

### Qwen2.5（日本語メイン）

| モデル | Ollama ID | サイズ(Q4) | 日本語 | 備考 |
|--------|-----------|-----------|--------|------|
| Qwen2.5 3B | `qwen2.5:3b` | ~2.0GB | ◎ | 軽量日本語 |
| Qwen2.5 7B | `qwen2.5:7b` | ~4.5GB | ◎ | **メイン推奨** |

### その他

| モデル | Ollama ID | サイズ(Q4) | 特徴 |
|--------|-----------|-----------|------|
| Phi-3.5 Mini | `phi3.5:mini` | ~2.4GB | コード生成 |
| Llama 3.2 3B | `llama3.2:3b` | ~2.2GB | 英語汎用 |
| Gemma 2 2B | `gemma2:2b` | ~1.8GB | 超軽量 |
| Mistral 7B | `mistral:7b` | ~4.1GB | 汎用品質高 |

## モデルの操作 (API)

```bash
# ダウンロード
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "qwen2.5:3b"}'

# インストール済み一覧
curl -s http://localhost:11434/api/tags | \
  python3 -c "import sys,json; [print(m['name']) for m in json.load(sys.stdin)['models']]"

# ロード中のモデル確認 (VRAMサイズ付き)
curl -s http://localhost:11434/api/ps | python3 -m json.tool

# 削除
curl -X DELETE http://localhost:11434/api/delete \
  -d '{"name": "model-name"}'
```

## ⚠️ 注意事項

- 8GB制約のため、**同時に複数モデルをロードしない**こと
- Jetson共有メモリの特性上、OSやシステムプロセスが約2GBを常時使用
- `/api/ps` でロード済みモデルを確認

## 📊 ベンチマーク結果

> 実測値は `benchmark/results/` に記録

| モデル | tokens/sec | TTFT(ms) | 計測日 |
|--------|-----------|----------|--------|
| - | - | - | 未計測 |
