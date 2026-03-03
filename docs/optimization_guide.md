# Jetson Orin Nano Super — 最大パフォーマンス化ガイド

## 速度のレイヤー構造

```
現在:  7 t/s  (CPU推論, 電源制限あり)
L1:   40 t/s  (GPU全オフロード + MAXN電源)          ← まずここ
L2:   55 t/s  (+ GGML_CUDA_FORCE_MMQ + Flash Attn)  ← 環境変数のみ
L3:   80 t/s  (+ 投機的デコーディング)               ← 2モデル同時起動
L4:  120+ t/s (TensorRT-LLM)                         ← 大工事・最終手段
```

---

## L1: GPU全オフロード（必須・今すぐ）

```bash
bash setup/09_optimize_perf.sh --apply
bash scripts/llama-server-optimized.sh /path/to/model.gguf

# 確認: GPU使用率が上がっているか
watch -n 1 nvidia-smi
```

**チェックポイント:**
- `-ngl 999` が指定されているか
- `nvidia-smi` で GPU 使用率 > 80%
- `nvpmodel -q` で MAXN モードか

---

## L2: CUDA量子化最適化（環境変数のみ・追加コストなし）

```bash
# llama-server 起動前に設定
export GGML_CUDA_FORCE_MMQ=1   # Q4_K_M等の量子化モデルでCUDA行列乗算を強制
export GGML_CUDA_NO_PEER_COPY=1
export CUDA_VISIBLE_DEVICES=0
```

**効果:** Q4_K_M モデルで +10〜30% 速度向上

> `scripts/llama-server-optimized.sh` には既に組み込み済み

---

## L3: 投機的デコーディング (Speculative Decoding)

小さいモデル（0.8B）で候補を先読みし、大きいモデル（4B）で検証。
長文生成・チャットで **2〜3x 速度向上** が期待できる。

```bash
# 必要なモデルを pull
# (Ollamaコンテナ内で)
curl -X POST http://localhost:11434/api/pull -d '{"name":"qwen3.5:4b-q4_K_M"}'
curl -X POST http://localhost:11434/api/pull -d '{"name":"qwen3.5:0.8b"}'

# 起動
bash scripts/speculative.sh \
  ~/.ollama/models/<qwen3.5-4b>.gguf \
  ~/.ollama/models/<qwen3.5-0.8b>.gguf
```

**制約:**
- メインモデル + ドラフトモデルの合計メモリが 5.2GB 以内に収まること
  - qwen3.5:4b (3.4GB) + qwen3.5:0.8b (1.0GB) = 4.4GB ✅

---

## L4: TensorRT-LLM（最大性能・大工事）

NVIDIA公式の推論エンジン。llama.cppより 2〜4x 高速だが、
モデルのコンパイル（エンジンビルド）が必要で時間がかかる。

**メリット:**
- INT8/INT4 + キャリブレーションで最高速度
- Jetson Orin 向けに最適化済み

**デメリット:**
- モデルごとに `trtllm-build` が必要（数十分〜数時間）
- セットアップが複雑
- 対応モデルに制限あり

**検討タイミング:** L1〜L3 で満足できない場合のみ

```bash
# 将来的に setup/10_setup_tensorrt.sh として実装予定
```

---

## マイルストーン別 残タスク

### M1（推論性能）— 今すぐ

```bash
# 1. 診断
bash scripts/diagnose.sh

# 2. 最適化適用
bash setup/09_optimize_perf.sh --apply

# 3. ベンチマーク
llama-cli -m model.gguf -ngl 999 --flash-attn -p "test" -n 100 2>&1 | grep "tok/s"

# 4. 結果を記録
# benchmark/results/YYYY-MM-DD.md にコミット
```

### M2（日本語品質）— M1後

```bash
# 評価スクリプト実行
bash eval/japanese_eval.sh                   # Ollama (11434)
bash eval/japanese_eval.sh llama 8081        # llama-server

# 結果を eval/results/ に保存してモデル選定
```

### M3（構造化出力）— M2後

```bash
# GBNF grammar でJSON出力を強制
llama-server \
  -m model.gguf \
  -ngl 999 --flash-attn \
  --grammar-file grammars/report.gbnf \
  --port 8083

# テスト: 任意の入力からレポートJSON が出力されるか確認
curl http://localhost:8083/v1/chat/completions \
  -d '{"messages": [{"role":"user","content":"以下をレポートにまとめて: バグ発見。ログイン画面でパスワードが空でも通過した。"}]}'
```

### M4（Tool Calling）— M3後

```bash
# tool calling テスト (Ollama)
curl http://localhost:11434/api/chat \
  -d '{
    "model": "qwen3.5:4b-q4_K_M",
    "messages": [{"role":"user","content":"東京の天気を調べて"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get weather info",
        "parameters": {
          "type": "object",
          "properties": {"city": {"type": "string"}},
          "required": ["city"]
        }
      }
    }]
  }'

# MCPサーバーとの接続は別途設計が必要
# → どのMCPサーバーを使うか Ryota と確認
```

### M5（テスト項目生成）— M4後

探索テストのログフォーマット設計が先決。
M4 の具体的な探索テストシナリオが決まったら実装。

### M6（OpenClaw統合）— M1後・並行可

```bash
# docs/openclaw_integration.md を参照
bash scripts/llama-server-optimized.sh model.gguf
# → OpenClaw の設定で http://<jetson-ip>:8081/v1 を登録
```

---

## llama.cpp コンパイル最適化（再ビルドが必要な変更）

現在の `setup/05_setup_llamacpp.sh` で使っているフラグに加えて、
以下を cmake に追加するとさらに高速化できる可能性がある:

```bash
cmake -B build \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=87 \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_CURL=ON \
  -DGGML_CUDA_F16=ON \          # FP16 演算を有効化
  -DGGML_CUDA_MMQ_Y=4           # 量子化行列乗算のブロックサイズ最適化
```

> ただし現時点では環境変数 (`GGML_CUDA_FORCE_MMQ=1`) で十分な場合が多い。
> 再ビルドはベンチマーク結果を見てから判断。

---

## 優先順位まとめ

| 優先度 | アクション | 効果 | コスト |
|--------|----------|------|--------|
| 🔴 最高 | `bash scripts/diagnose.sh` で現状確認 | 問題特定 | 30秒 |
| 🔴 最高 | `-ngl 999` + MAXN電源モード | 7→40 t/s | 5分 |
| 🟠 高 | `GGML_CUDA_FORCE_MMQ=1` 設定 | +10〜30% | 0分（設定済み） |
| 🟠 高 | `qwen3.5:4b-q4_K_M` pull・確認 | M2〜M6の基盤 | pullのみ |
| 🟡 中 | 投機的デコーディング試行 | +50〜200% | 30分 |
| 🟡 中 | `eval/japanese_eval.sh` 実行でM2評価 | モデル選定 | 15分 |
| 🟢 低 | TensorRT-LLM 導入 | +200〜400% | 半日〜 |
