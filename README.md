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
# ワンショットセットアップ（推奨）
bash install.sh
```

これ1本で Docker Ollama の起動からスターターモデルの取得まで完了する。

<details>
<summary>個別スクリプトで実行する場合</summary>

```bash
# 1. 環境確認
bash setup/00_jetpack_check.sh

# 2. Docker Ollama セットアップ
bash setup/05_setup_docker_ollama.sh

# 3. モデル一括ダウンロード
bash setup/03_pull_models.sh
```

</details>

## ドキュメント

| ドキュメント | 内容 |
|------------|------|
| [models/model_list.md](models/model_list.md) | 対応モデル一覧・ベンチマーク結果 |
| [docs/lfm25_setup.md](docs/lfm25_setup.md) | LFM-2.5 セットアップ詳細 |
| [docs/lfm25_japanese.md](docs/lfm25_japanese.md) | LFM-2.5 日本語モデル調査 |
| [docs/api_usage.md](docs/api_usage.md) | OpenAI互換API使い方（Python/TS） |
| [docs/troubleshooting.md](docs/troubleshooting.md) | トラブルシューティング |

## セットアップスクリプト

| スクリプト | 内容 |
|-----------|------|
| `install.sh` | **ワンショットセットアップ（推奨）** |
| `setup/00_jetpack_check.sh` | 環境・JetPack確認 |
| `setup/05_setup_docker_ollama.sh` | Docker Ollama セットアップ単体 |
| `setup/03_pull_models.sh` | 推奨モデル一括 pull |
| `setup/04_setup_webui.sh` | Open WebUI (ブラウザUI) |
| `setup/01_install_ollama.sh` | ネイティブ Ollama インストール (旧) |
| `setup/02_install_llamacpp.sh` | llama.cpp CUDA ビルド |

## 推論フレームワーク

- **Ollama** (メイン) — OpenAI互換API・管理が楽
- **llama.cpp** (チューニング用) — GPU layer数の細かい制御

## 対応モデル（主要）

| モデル | サイズ | 日本語 | 用途 |
|--------|--------|--------|------|
| LFM-2.5 3B | ~2.0GB | △ | 省メモリ・高速 |
| LFM-2.5 7B | ~4.5GB | △ | 高品質 |
| Qwen2.5 7B | ~4.5GB | ◎ | 日本語メイン |
| Phi-3.5 Mini | ~2.4GB | △ | コード生成 |
| Gemma 2 2B | ~1.8GB | △ | 超軽量 |

詳細 → [models/model_list.md](models/model_list.md)

## 進捗

- [x] リポジトリ構成・スクリプト整備
- [x] Ollama / llama.cpp セットアップスクリプト
- [x] 推奨モデル選定・一覧
- [x] LFM-2.5 セットアップドキュメント
- [x] LFM-2.5 日本語モデル調査
- [x] OpenAI互換 API 使い方ドキュメント
- [x] トラブルシューティングガイド
- [x] Open WebUI セットアップ
- [ ] Jetsonでの実機セットアップ実行
- [ ] ベンチマーク実測値の記録
- [ ] LFM-2.5 日本語fine-tune版の発見・検証
- [ ] llama.cpp CUDA ビルド実機確認
- [ ] Open WebUI 動作確認

## ライセンス

MIT
