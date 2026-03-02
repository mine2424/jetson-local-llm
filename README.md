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

これ1本で jetson-containers による Ollama コンテナ起動からスターターモデルの取得まで完了する。

<details>
<summary>個別スクリプトで実行する場合</summary>

```bash
# 1. 環境確認
bash setup/00_jetpack_check.sh

# 2. jetson-containers 経由で Ollama セットアップ (autotag でイメージ自動解決)
bash setup/08_setup_jetson_containers.sh

# 3. モデルのダウンロード (API経由)
curl -X POST http://localhost:11434/api/pull \
  -d '{"name":"qwen2.5:3b"}'
```

</details>

## アーキテクチャ

Ollama は **Docker コンテナ**として動作する。イメージは `autotag` コマンドが JetPack バージョンに合わせて自動解決するため、バージョン番号のハードコードが不要。

```
jetson-containers autotag ollama
  → dustynv/ollama:r36.x.x  (JetPack に対応したイメージを自動選択)
```

Ollama との通信は **HTTP API のみ** (`http://localhost:11434`)。

## ドキュメント

| ドキュメント | 内容 |
|------------|------|
| [models/model_list.md](models/model_list.md) | 対応モデル一覧・ベンチマーク結果 |
| [docs/quickstart.md](docs/quickstart.md) | 起動・テストの最短手順 |
| [docs/docker_ollama.md](docs/docker_ollama.md) | Docker Ollama / jetson-containers 詳細 |
| [docs/lfm25_setup.md](docs/lfm25_setup.md) | LFM-2.5 セットアップ詳細 |
| [docs/lfm25_japanese.md](docs/lfm25_japanese.md) | LFM-2.5 日本語モデル調査 |
| [docs/api_usage.md](docs/api_usage.md) | OpenAI互換API使い方（Python/TS） |
| [docs/troubleshooting.md](docs/troubleshooting.md) | トラブルシューティング |

## セットアップスクリプト

| スクリプト | 内容 |
|-----------|------|
| `install.sh` | **ワンショットセットアップ（推奨）** |
| `setup/00_jetpack_check.sh` | 環境・JetPack確認 |
| `setup/08_setup_jetson_containers.sh` | jetson-containers + autotag Ollama セットアップ |
| `setup/04_setup_webui.sh` | Open WebUI (ブラウザUI) |
| `setup/06_setup_lfm.sh` | LFM-2.5 GGUF インポート |
| `setup/07_setup_memory_opt.sh` | SSD スワップ / ZRAM 無効化 / GUI 無効化 |

## 推論フレームワーク

- **Ollama** (メイン) — OpenAI互換API・管理が楽・Docker コンテナで動作

## 対応モデル（主要）

| モデル | サイズ | 日本語 | 用途 |
|--------|--------|--------|------|
| LFM-2.5 1.2B | ~0.7GB | △ | 省メモリ・高速推論 |
| Qwen2.5 3B | ~2.0GB | ◎ | 軽量日本語 |
| Qwen2.5 7B | ~4.5GB | ◎ | 日本語メイン |
| Phi-3.5 Mini | ~2.4GB | △ | コード生成 |
| Gemma 2 2B | ~1.8GB | △ | 超軽量 |

詳細 → [models/model_list.md](models/model_list.md)

## 進捗

- [x] リポジトリ構成・スクリプト整備
- [x] jetson-containers / autotag セットアップ
- [x] 推奨モデル選定・一覧
- [x] LFM-2.5 セットアップドキュメント
- [x] LFM-2.5 日本語モデル調査
- [x] OpenAI互換 API 使い方ドキュメント
- [x] トラブルシューティングガイド
- [x] Open WebUI セットアップ
- [x] メモリ最適化スクリプト
- [ ] Jetsonでの実機セットアップ実行
- [ ] ベンチマーク実測値の記録
- [ ] LFM-2.5 日本語fine-tune版の発見・検証

## ライセンス

MIT
