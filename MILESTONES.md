# Jetson Orin Nano Super — ローカルLLM マイルストーン

## 最終目標

Jetson Orin Nano Super 上のローカルLLMで以下を実現する:

| # | 目標 |
|---|------|
| A | 与えられた情報から指定フォーマットでレポートを出力 |
| B | 探索的テストにおける Tool Calling / MCP 連携 |
| C | 探索テストの結果からテスト項目を生成 |
| D | 日本語の校正作業 |
| E | OpenClaw で使える推論力 |

---

## マイルストーン全体図

```
M1 推論性能確立
    └── M2 日本語品質確立 ──── 目標 D (日本語校正)
            └── M3 構造化出力 ──── 目標 A (レポート生成)
                    └── M4 Tool Calling + MCP ──── 目標 B (探索テスト)
                                └── M5 テスト項目生成 ──── 目標 C
M1 ──────────────────────────────── M6 OpenClaw統合 ──── 目標 E
```

---

## M1: 推論性能基盤確立

> **前提**: これが通らないと全て始まらない

### やること
- [ ] GPU 全オフロード確認（`-ngl 999` で GPU が使われているか）
- [ ] `sudo nvpmodel -m 0` + `sudo jetson_clocks` 適用済み確認
- [ ] `bash scripts/diagnose.sh` を実行して現状把握
- [ ] Qwen3.5:4b-q4_K_M をベースモデルとして pull・動作確認

### 成功基準
- ✅ llama.cpp 推論速度: **40 t/s 以上**（現状 7 t/s）
- ✅ `nvidia-smi` で GPU 使用率 > 80% 確認
- ✅ 10分間の連続推論で OOM なし

### 使用コマンド
```bash
bash scripts/diagnose.sh
bash setup/09_optimize_perf.sh --apply
bash scripts/llama-server-optimized.sh ~/.ollama/models/...
```

### 推奨モデル
| モデル | サイズ | 理由 |
|--------|--------|------|
| `qwen3.5:4b-q4_K_M` | 3.4GB | **M1〜M6 全目標のベースモデル** |

---

## M2: 日本語品質確立

> **依存**: M1完了後

### やること
- [ ] 日本語品質ベンチマーク実施（校正・要約・翻訳タスク）
- [ ] Qwen3.5:4b vs Qwen2.5:7b の日本語品質比較
- [ ] LFM2.5-JP（`nn-tsuzu/LFM2.5-1.2B-JP`）の日本語品質確認
- [ ] モデル確定

### 評価タスク（手動）
```
1. 誤字脱字修正: 「私はりんごを買いました。昨日のことだ」→ 自然な文体に
2. 敬体統一: 「〜です。〜だ。〜ます。」→ 敬体/常体を統一
3. 要約: 500文字の文章 → 100文字以内に要約
4. 語彙改善: 「やばい実装をした」→ ビジネス文書用に言い換え
```

### 成功基準
- ✅ 校正タスクで修正が**的確かつ見落としなし**（人間が確認）
- ✅ 要約が指定文字数に収まり、内容が正確
- ✅ 応答が常に日本語で返ってくる

### 推奨モデル
| モデル | サイズ | 備考 |
|--------|--------|------|
| `qwen3.5:4b-q4_K_M` | 3.4GB | 第一候補 |
| `qwen2.5:7b-instruct-q4_K_M` | 4.7GB | 日本語最強クラス・ギリギリ動く |
| `nn-tsuzu/LFM2.5-1.2B-JP` | 0.7GB | 速度優先の場合 |

---

## M3: 構造化出力 / レポート生成

> **依存**: M2完了後

### やること
- [ ] JSON 形式の構造化出力が安定して動くか確認
- [ ] レポートテンプレートの設計（Markdown / JSON）
- [ ] システムプロンプトで出力フォーマットを強制する手法の確立
- [ ] llama.cpp の Grammar 機能（JSON schema enforcement）を試す

### レポートテンプレート（例）
```json
{
  "title": "探索テストレポート",
  "date": "2026-xx-xx",
  "summary": "...",
  "findings": [
    { "id": 1, "severity": "high|medium|low", "description": "...", "steps": [...] }
  ],
  "recommendations": ["..."]
}
```

### 成功基準
- ✅ 指定 JSON スキーマに**常に**準拠した出力（JSON パースエラーなし）
- ✅ Markdown レポートが指定セクション構成を維持
- ✅ 複数の異なる入力情報から一貫したフォーマットで出力

### 実装ポイント
```bash
# llama.cpp の Grammar 機能でスキーマ強制
llama-server \
  --grammar-file report_schema.gbnf \
  ...
```

---

## M4: Tool Calling + MCP 連携（探索テスト）

> **依存**: M3完了後

### やること
- [ ] Ollama / llama-server の tool calling 動作確認
- [ ] MCP サーバーとの接続確認（ローカル or ネットワーク）
- [ ] 探索的テストシナリオの実装（スクリーン操作・API呼び出し等）
- [ ] エージェントループが安定して動くか確認

### Tool Calling 確認コマンド
```bash
# Ollama tool calling テスト
curl http://localhost:11434/api/chat \
  -d '{
    "model": "qwen3.5:4b-q4_K_M",
    "messages": [{"role": "user", "content": "東京の天気を調べて"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get weather for a city",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string"}
          }
        }
      }
    }]
  }'
```

### MCP 構成案
```
Jetson (llama-server :8081)
    ↕ OpenAI-compatible API
MCP Host (同一 or ネットワーク)
    ↕ MCP Protocol
MCP Servers:
  - filesystem (テスト対象アプリ操作)
  - browser-use (UI探索)
  - custom (テスト専用ツール)
```

### 成功基準
- ✅ Tool Calling: モデルが適切なツールを選択・引数を生成
- ✅ MCP: ツール結果をコンテキストに取り込んで次の判断ができる
- ✅ 探索的テストシナリオで 5 ステップ以上のエージェントループが安定動作

### 推奨モデル
| モデル | Tool Calling | 備考 |
|--------|-------------|------|
| `qwen3.5:4b-q4_K_M` | ✅ネイティブ対応 | **最推奨** |
| `qwen2.5:7b-instruct-q4_K_M` | ✅対応 | メモリ注意 |

---

## M5: テスト項目生成

> **依存**: M4完了後

### やること
- [ ] 探索テストのログ/結果から自動でテストケースを生成
- [ ] テスト項目の形式設計（ID / 前提条件 / 手順 / 期待結果）
- [ ] 重複排除・優先度付けロジック
- [ ] 出力形式: Markdown / CSV / JIRA互換 JSON

### テスト項目テンプレート
```markdown
## テストケース TC-001

**カテゴリ**: 機能テスト / 入力バリデーション
**優先度**: High
**前提条件**: ユーザーがログイン済み

**手順**:
1. XXX 画面を開く
2. フォームに YYY を入力
3. 送信ボタンを押す

**期待結果**: ZZZ が表示される
**探索テストで発見**: [セッション ID / 日時]
```

### 成功基準
- ✅ 探索テストの 1 セッション（30分）から **10件以上**のテスト項目を自動生成
- ✅ 生成された項目が**そのまま使える**品質（手修正 < 20%）
- ✅ 重複・矛盾するテスト項目が排除されている

---

## M6: OpenClaw 統合

> **依存**: M1完了後（M2〜M5 と並行可）

### やること
- [ ] llama-server を OpenClaw のカスタム LLM プロバイダーとして登録
- [ ] OpenClaw の推論タスクをローカルLLMで実行
- [ ] レイテンシ・品質のトレードオフ評価
- [ ] 用途別のモデル切り替え設定

### OpenClaw 接続設定
```yaml
# openclaw config
providers:
  local-jetson:
    type: openai-compatible
    base_url: http://<jetson-ip>:8081/v1
    model: qwen3.5-4b   # llama-server のモデル名
    api_key: none
```

### 成功基準
- ✅ OpenClaw から Jetson ローカルLLM で **基本的な会話タスク**が完結
- ✅ 単純な要約・分類タスクを **30秒以内**で完了
- ✅ エラーなく 10回連続でリクエストが成功

### 推奨モデル
| 用途 | モデル | 理由 |
|------|--------|------|
| 汎用推論 | `qwen3.5:4b-q4_K_M` | 速度・品質バランス |
| 日本語重視 | `qwen2.5:7b-instruct-q4_K_M` | 最高品質・低速 |
| 速度重視 | `qwen3.5:2b-q4_K_M` | 軽量・高速 |

---

## 進捗トラッキング

| マイルストーン | ステータス | 目標 |
|--------------|-----------|------|
| M1: 推論性能確立 | 🔧 進行中 | 40+ t/s |
| M2: 日本語品質確立 | ⏳ 未着手 | 目標 D |
| M3: 構造化出力 | ⏳ 未着手 | 目標 A |
| M4: Tool Calling + MCP | ⏳ 未着手 | 目標 B |
| M5: テスト項目生成 | ⏳ 未着手 | 目標 C |
| M6: OpenClaw 統合 | ⏳ 未着手 | 目標 E |

---

## モデル選定まとめ

> M1 完了後は `qwen3.5:4b-q4_K_M` を **全マイルストーンの主力** として使う

```
メモリ使用量:
  qwen3.5:4b-q4_K_M    3.4GB  ← M1-M6 全対応
  qwen2.5:7b-q4_K_M    4.7GB  ← M2/M6 日本語品質優先時
  LFM2.5-1.2B-JP       0.7GB  ← M2 速度検証用
  
  8GB Jetson の安全ライン: ~5.2GB
```
