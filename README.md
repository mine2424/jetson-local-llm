# 🤖 Jetson Local LLM

**Jetson Orin Nano Super** でローカルLLMを動かすための環境構築リポジトリ。

## ハードウェア仕様

| 項目 | スペック |
|------|---------|
| GPU | 1024-core NVIDIA Ampere / 32 Tensor Cores |
| RAM | 8GB LPDDR5（CPU/GPU共有） |
| Storage | 256GB NVMe SSD |
| OS | JetPack 6.x (Ubuntu 22.04) |
| 消費電力 | 7〜25W |

## クイックスタート

```bash
# 1. 依存関係チェック
bash setup/00_jetpack_check.sh

# 2. Ollama インストール
bash setup/01_install_ollama.sh

# 3. 推奨モデル一括ダウンロード
bash setup/03_pull_models.sh

# 4. 動作確認
bash benchmark/run_bench.sh
```

## 対応モデル

→ [models/model_list.md](models/model_list.md) を参照

## ディレクトリ構成

```
jetson-local-llm/
├── setup/           # セットアップスクリプト
├── models/          # モデル情報・検証結果
├── config/          # Ollama・systemd設定
├── benchmark/       # ベンチマークスクリプト
└── docs/            # 詳細ドキュメント
```

## 推論フレームワーク

- **Ollama** (メイン) - OpenAI互換API・管理が楽
- **llama.cpp** (チューニング) - GPU layer数の細かい制御

## ライセンス

MIT
