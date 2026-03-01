# Docker Ollama セットアップ & 使い方ガイド

Jetson Orin Nano Super (8GB) で **Docker コンテナ版 Ollama** を使ってローカル LLM を動かすための完全ガイド。

---

## なぜ Docker が必要なのか

### native Ollama の問題 (CUDA OOM)

Jetson の GPU メモリアロケータ (NvMap) は **`MemFree`** からしか割り当てられない。
`MemAvailable` に含まれるページキャッシュは再利用できない。

```
MemTotal:        7993 MB
MemFree:         1300 MB   ← NvMap が使えるのはここだけ
MemAvailable:    5000 MB   ← ページキャッシュ含む。NvMap からは見えない
```

結果として、システム全体には余裕があっても NvMap 割り当てが失敗し
`CUDA error: out of memory` が発生する。

### Docker コンテナ版が解決する点

| 問題 | 解決策 |
|------|--------|
| NvMap が MemFree しか使えない | 起動前に `drop_caches` でページキャッシュを解放し MemFree を増やす |
| `vm.min_free_kbytes` が低い | `2097152`（2GB）に設定し常時 MemFree を確保 |
| native Ollama の CUDA ライブラリが不一致 | `dustynv/ollama` は L4T R36.x 向けに正しくビルド済み |

> **API 互換性**: コンテナ起動後は `http://localhost:11434` で同じ REST API が使える。
> 既存の `ollama pull` / `ollama run` コマンドはそのまま動く。

---

## 前提条件

| 項目 | 必要なバージョン / 状態 |
|------|-------------------------|
| JetPack | L4T R36.4.x (JetPack 6.x) |
| Docker | 20.10 以上（本プロジェクトでは 29.2.1 確認済み） |
| `/etc/docker/daemon.json` | `nvidia` runtime が設定済み |
| ストレージ | モデル保存用に 20GB 以上推奨 |

### 確認コマンド

```bash
# JetPack バージョン
cat /etc/nv_tegra_release

# Docker バージョン
docker --version

# nvidia runtime 設定確認
cat /etc/docker/daemon.json
```

期待する `daemon.json` の内容:

```json
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "default-runtime": "nvidia"
}
```

---

## セットアップ

### TUI メニューから（推奨）

```bash
./menu.sh
```

`4. Setup → 6. Docker Ollama セットアップ` を選択して実行。

画面の指示に従うだけで以下がすべて自動実行される。

### コマンドラインから（手動）

```bash
bash setup/05_setup_docker_ollama.sh
```

スクリプトが行う処理:

```
[1/8] Docker デーモンを有効化・起動
[2/8] nvidia-container-runtime の確認・インストール
[3/8] nvidia-smi スモークテスト
[4/8] ネイティブ Ollama サービスを停止・無効化
[5/8] vm.min_free_kbytes = 2097152 を sysctl に適用
[6/8] ページキャッシュを解放 (drop_caches)
[7/8] dustynv/ollama:r36.4.0 コンテナを作成・起動
[8/8] API 応答を確認
```

---

## コンテナの構成

セットアップで作成されるコンテナの詳細:

```bash
docker run -d \
  --name ollama \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e OLLAMA_FLASH_ATTENTION=1 \      # VRAM 使用量 30〜40% 削減
  -e OLLAMA_MAX_LOADED_MODELS=1 \    # 同時ロード上限 1 モデル
  -e OLLAMA_KEEP_ALIVE=5m \          # アイドル 5 分でモデルをアンロード
  -e OLLAMA_NUM_CTX=2048 \           # KV キャッシュ 3.7GB → 234MB
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v "$HOME/.ollama:/root/.ollama" \ # モデルをホストに永続化
  -p 127.0.0.1:11434:11434 \
  --restart unless-stopped \
  dustynv/ollama:r36.4.0
```

| 設定 | 意味 |
|------|------|
| `OLLAMA_FLASH_ATTENTION=1` | Flash Attention で VRAM を節約 |
| `OLLAMA_MAX_LOADED_MODELS=1` | 複数モデルの同時ロードを禁止 (OOM 防止) |
| `OLLAMA_KEEP_ALIVE=5m` | アイドル後にモデルを GPU メモリから解放 |
| `OLLAMA_NUM_CTX=2048` | コンテキスト長を抑えて KV キャッシュを小さくする |
| `-v ~/.ollama:/root/.ollama` | モデルファイルはホスト側に保存（コンテナ削除後も残る）|
| `-p 127.0.0.1:11434:11434` | localhost からのみアクセス可 |

---

## 日常的な操作

### TUI メニューから

```bash
./menu.sh
```

`3. Service` メニューに Docker コンテナ対応の操作がある:

| 項目 | 動作 |
|------|------|
| `2. Ollama 起動` | `drop_caches` → `docker start ollama` |
| `3. Ollama 停止` | `docker stop ollama` |
| `4. Ollama 再起動` | stop → `drop_caches` → start |
| `5. Ollamaログ表示` | `docker logs --tail 50 ollama` |
| `1. ステータス確認` | Docker コンテナ状態 + API 応答 + メモリ |

### コマンドラインから

```bash
# 起動 (必ず drop_caches を先に実行)
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
docker start ollama

# 停止
docker stop ollama

# 再起動
docker restart ollama

# 状態確認
docker ps --filter name=ollama

# ログ確認 (リアルタイム)
docker logs -f ollama

# API 確認
curl http://localhost:11434/api/tags
```

---

## モデルの管理

### TUI メニューから

`2. Models` メニューからモデルの pull / テスト / 削除ができる（Docker 起動中であれば同じ操作が使える）。

### コマンドラインから

モデルはホスト側コマンドでも、コンテナ内でも操作できる。

```bash
# --- ホスト側から (OLLAMA_HOST 経由) ---
ollama pull qwen2.5:3b
ollama pull qwen2.5:7b
ollama list

# --- コンテナ内から ---
docker exec -it ollama ollama pull qwen2.5:3b
docker exec -it ollama ollama list
```

### 推奨モデル (Jetson 8GB 向け)

| モデル | サイズ | MemFree 目安 | 用途 |
|--------|--------|-------------|------|
| `qwen2.5:3b` | ~2.0 GB | 2.5 GB あれば OK | 日本語・軽量 |
| `qwen2.5:7b` | ~4.5 GB | 5 GB 以上必要 | 日本語・高品質 |
| `gemma2:2b` | ~1.8 GB | 2 GB あれば OK | 動作確認・最軽量 |
| `phi3.5:mini` | ~2.4 GB | 3 GB あれば OK | コード生成 |

> **メモリ確認**: `free -h` の `free` 列が目安。`MemFree` が不足する場合は
> `sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'` を実行してから pull する。

---

## モデルの実行

```bash
# 対話モード (Ctrl+D または /bye で終了)
ollama run qwen2.5:3b

# 1 回だけ実行
ollama run qwen2.5:3b "日本語で自己紹介してください"

# コンテナ内で実行
docker exec -it ollama ollama run qwen2.5:3b "hello"
```

### ロード中モデルの確認

```bash
# どのモデルが VRAM を占有しているか
ollama ps
# または
docker exec ollama ollama ps
```

出力例:

```
NAME           ID        SIZE    PROCESSOR    UNTIL
qwen2.5:3b    abc123    2.0 GB  100% GPU     5 minutes from now
```

`PROCESSOR` が `100% GPU` であれば GPU 推論が正常に動作している。

---

## API の使い方

コンテナが起動していれば `http://localhost:11434` で OpenAI 互換 API が使える。

### curl

```bash
# モデル一覧
curl http://localhost:11434/api/tags | python3 -m json.tool

# OpenAI 互換チャット
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5:3b",
    "messages": [
      {"role": "user", "content": "日本語で自己紹介してください"}
    ]
  }' | python3 -m json.tool
```

### Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama",  # 任意の文字列でOK
)

response = client.chat.completions.create(
    model="qwen2.5:3b",
    messages=[
        {"role": "system", "content": "あなたは日本語で答えるAIです。"},
        {"role": "user", "content": "Jetsonでローカル LLM を動かす利点は？"},
    ],
    temperature=0.7,
    max_tokens=512,
)
print(response.choices[0].message.content)
```

### LAN 内の別マシンからアクセスする

コンテナはデフォルトで `127.0.0.1:11434` のみ公開している。
LAN からアクセスしたい場合はコンテナを作り直す:

```bash
# 既存コンテナを削除
docker stop ollama && docker rm ollama

# LAN に公開して再作成 (0.0.0.0 でバインド)
docker run -d \
  --name ollama \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e OLLAMA_FLASH_ATTENTION=1 \
  -e OLLAMA_MAX_LOADED_MODELS=1 \
  -e OLLAMA_KEEP_ALIVE=5m \
  -e OLLAMA_NUM_CTX=2048 \
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v "$HOME/.ollama:/root/.ollama" \
  -p 11434:11434 \
  --restart unless-stopped \
  dustynv/ollama:r36.4.0
```

別マシンからは `http://<jetson-ip>:11434` でアクセスできる。

詳しい API の使い方 → `docs/api_usage.md`

---

## リソース監視

```bash
# メモリ確認 (MemFree に注目)
watch -n 2 'grep -E "MemFree|MemAvailable" /proc/meminfo'

# GPU / CPU リアルタイム監視
tegrastats --interval 1000

# コンテナのリソース使用量
docker stats ollama
```

### tegrastats の読み方

```
RAM 5200/7993MB (lfb 1x2MB)  GR3D_FREQ 98%  CPU [12%@...]
 ^--- RAM使用量                 ^--- GPU使用率 (高いほど良い)
```

`GR3D_FREQ` が 0% のままなら GPU が使われていない（CPU 推論になっている）。

---

## トラブルシューティング

### ❌ `CUDA error: out of memory` が依然発生する

```bash
# MemFree を確認
grep MemFree /proc/meminfo
# → 1500000 kB 未満なら drop_caches が必要

# キャッシュを手動で解放してから再起動
docker stop ollama
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
sleep 2
grep MemFree /proc/meminfo   # 3GB 以上あれば OK
docker start ollama
```

### ❌ コンテナが起動しない / すぐ落ちる

```bash
# ログを確認
docker logs ollama

# nvidia runtime が効いているか確認
docker run --rm --runtime nvidia dustynv/l4t-base:r36.4.0 nvidia-smi

# daemon.json を確認
cat /etc/docker/daemon.json
sudo systemctl restart docker
```

### ❌ `nvidia-container-runtime` が見つからない

```bash
sudo apt-get update
sudo apt-get install -y nvidia-container
# または
sudo apt-get install -y nvidia-container-runtime

which nvidia-container-runtime  # /usr/bin/nvidia-container-runtime が出ればOK
```

### ❌ API が応答しない (コンテナは Up なのに)

```bash
# コンテナ内で Ollama が起動中か確認
docker exec ollama ps aux | grep ollama

# ポートフォワードを確認
docker port ollama

# ポートが使用中か確認
ss -tlnp | grep 11434
```

### ❌ モデルが GPU ではなく CPU で動く

```bash
# 実行中モデルの processor を確認
docker exec ollama ollama ps
# PROCESSOR が "100% CPU" なら GPU 割り当て失敗

# MemFree を増やして再試行
docker restart ollama
```

### ❌ `docker: Error response from daemon: Unknown runtime specified nvidia`

`daemon.json` の nvidia runtime 設定が効いていない:

```bash
# 設定確認
cat /etc/docker/daemon.json

# 設定が正しければ Docker を再起動
sudo systemctl restart docker

# それでも解決しない場合は nvidia-container を再インストール
sudo apt-get install --reinstall nvidia-container
```

---

## 設定の調整

### コンテキスト長を増やしたい

`OLLAMA_NUM_CTX=2048` はメモリ節約のためのデフォルト値。
モデルにより最大コンテキスト長が異なるので、メモリに余裕があれば増やせる:

```bash
# コンテナを停止・削除して再作成
docker stop ollama && docker rm ollama

docker run -d \
  --name ollama \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e OLLAMA_FLASH_ATTENTION=1 \
  -e OLLAMA_MAX_LOADED_MODELS=1 \
  -e OLLAMA_KEEP_ALIVE=5m \
  -e OLLAMA_NUM_CTX=4096 \           # 2048 → 4096 に変更
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v "$HOME/.ollama:/root/.ollama" \
  -p 127.0.0.1:11434:11434 \
  --restart unless-stopped \
  dustynv/ollama:r36.4.0
```

### vm.min_free_kbytes の確認・変更

```bash
# 現在の設定確認
cat /etc/sysctl.d/99-ollama-jetson.conf
sysctl vm.min_free_kbytes

# より大きいモデルを使う場合は増やす (例: 3GB)
sudo sysctl -w vm.min_free_kbytes=3145728
```

---

## ネイティブ Ollama に戻す場合

Docker Ollama をやめてネイティブ Ollama に戻す手順:

```bash
# Docker コンテナを停止（削除はしない）
docker stop ollama

# ネイティブ Ollama サービスを再有効化
sudo systemctl enable --now ollama

# sysctl の設定はそのまま残しても問題ない
# (vm.min_free_kbytes=2097152 はネイティブでも有効)
```

---

## 関連ドキュメント

- `docs/quickstart.md` — Ollama 起動 & テストの最短手順
- `docs/api_usage.md` — OpenAI 互換 API の詳細
- `docs/troubleshooting.md` — その他のトラブルシューティング
- `models/model_list.md` — 推奨モデル全一覧
