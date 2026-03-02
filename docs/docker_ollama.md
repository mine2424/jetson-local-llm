# Docker Ollama セットアップ & 使い方ガイド

Jetson Orin Nano Super (8GB) で **jetson-containers** を使って Ollama コンテナを動かすための完全ガイド。

---

## なぜ Docker + jetson-containers が必要なのか

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

### jetson-containers が解決する点

| 問題 | 解決策 |
|------|--------|
| NvMap が MemFree しか使えない | 起動前に `drop_caches` でページキャッシュを解放し MemFree を増やす |
| `vm.min_free_kbytes` が低い | `2097152`（2GB）に設定し常時 MemFree を確保 |
| native Ollama の CUDA ライブラリが不一致 | `dustynv/ollama` は L4T 向けに正しくビルド済み |
| イメージタグのハードコード | `autotag ollama` が JetPack バージョンに合ったタグを自動解決 |

> **API 互換性**: コンテナ起動後は `http://localhost:11434` で REST API が使える。

---

## autotag とは

`jetson-containers` が提供する CLI ツール。実行中の JetPack/L4T バージョンを検出し、
対応した Docker イメージタグを返す。

```bash
autotag ollama
# → dustynv/ollama:r36.4.0  (JetPack 6.1 の場合)
# → dustynv/ollama:r36.3.0  (JetPack 6.0 の場合)
```

バージョン番号をハードコードする必要がなくなる。

---

## 前提条件

| 項目 | 必要なバージョン / 状態 |
|------|-------------------------|
| JetPack | L4T R36.x (JetPack 6.x) |
| Docker | 20.10 以上 |
| git | クローン用 |
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

`4. Setup → 2. jetson-containers セットアップ` を選択して実行。

### コマンドラインから（手動）

```bash
bash setup/08_setup_jetson_containers.sh
```

スクリプトが行う処理:

```
[1/6] 前提条件チェック (git, Docker, nvidia-container-runtime)
[2/6] jetson-containers インストール (git clone + install.sh)
[3/6] autotag ollama でイメージ名を解決
[4/6] vm.min_free_kbytes = 2097152 + ページキャッシュ解放
[5/6] 既存コンテナの停止・削除
[6/6] Docker コンテナ起動 (動的イメージ)
[Wait] API 応答確認 (最大30秒)
```

---

## コンテナの構成

```bash
# autotag で解決したイメージを使用
IMAGE=$(autotag ollama)

docker run -d \
  --name ollama \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e OLLAMA_FLASH_ATTENTION=1 \      # VRAM 使用量 30〜40% 削減
  -e OLLAMA_MAX_LOADED_MODELS=1 \    # 同時ロード上限 1 モデル
  -e OLLAMA_KEEP_ALIVE=5m \          # アイドル 5 分でモデルをアンロード
  -e OLLAMA_NUM_CTX=2048 \           # KV キャッシュ 3.7GB → 234MB
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v "$HOME/.ollama/models:/data/models/ollama/models" \
  -p 127.0.0.1:11434:11434 \
  --restart unless-stopped \
  "$IMAGE" \
  /bin/sh -c '/start_ollama; tail -f /data/logs/ollama.log'
```

| 設定 | 意味 |
|------|------|
| `OLLAMA_FLASH_ATTENTION=1` | Flash Attention で VRAM を節約 |
| `OLLAMA_MAX_LOADED_MODELS=1` | 複数モデルの同時ロードを禁止 (OOM 防止) |
| `OLLAMA_KEEP_ALIVE=5m` | アイドル後にモデルを GPU メモリから解放 |
| `OLLAMA_NUM_CTX=2048` | コンテキスト長を抑えて KV キャッシュを小さくする |
| `-v ~/.ollama/models:...` | モデルファイルはホスト側に保存（コンテナ削除後も残る）|
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
| `3. Ollama 停止` | API でモデルアンロード → `docker stop ollama` |
| `4. Ollama 再起動` | stop → `drop_caches` → start |
| `5. Ollamaログ表示` | `docker logs --tail 50 ollama` |
| `1. ステータス確認` | Docker コンテナ状態 + API 応答 + メモリ |

### コマンドラインから

```bash
# 起動 (必ず drop_caches を先に実行)
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
sudo docker start ollama

# 停止
sudo docker stop ollama

# 再起動
sudo docker stop ollama && sudo docker start ollama

# 状態確認
sudo docker ps --filter name=ollama

# ログ確認 (リアルタイム)
sudo docker logs -f ollama

# API 確認
curl http://localhost:11434/api/tags
```

---

## モデルの管理

### TUI メニューから

`2. Models` メニューからモデルの pull / テスト / 削除ができる。

### API から

```bash
# --- モデルのダウンロード ---
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "qwen2.5:3b"}'

# --- インストール済みモデル一覧 ---
curl -s http://localhost:11434/api/tags | \
  python3 -c "import sys,json; [print(m['name']) for m in json.load(sys.stdin)['models']]"

# --- ロード中モデルの確認 ---
curl -s http://localhost:11434/api/ps | python3 -m json.tool

# --- モデルの削除 ---
curl -X DELETE http://localhost:11434/api/delete \
  -d '{"name": "model-name"}'
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
# API で生成 (stream: false で結果を一括取得)
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5:3b",
    "prompt": "日本語で自己紹介してください",
    "stream": false
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"
```

### ロード中モデルのアンロード

```bash
# keep_alive=0 でモデルを VRAM から解放
curl -s -X POST http://localhost:11434/api/generate \
  -d '{"model": "qwen2.5:3b", "keep_alive": 0}'
```

---

## API の使い方

コンテナが起動していれば `http://localhost:11434` で OpenAI 互換 API が使える。

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

詳しい API の使い方 → `docs/api_usage.md`

---

## リソース監視

```bash
# メモリ確認 (MemFree に注目)
watch -n 2 'grep -E "MemFree|MemAvailable" /proc/meminfo'

# GPU / CPU リアルタイム監視
tegrastats --interval 1000

# コンテナのリソース使用量
sudo docker stats ollama
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
sudo docker stop ollama
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
sleep 2
grep MemFree /proc/meminfo   # 3GB 以上あれば OK
sudo docker start ollama
```

### ❌ コンテナが起動しない / すぐ落ちる

```bash
# ログを確認
sudo docker logs ollama

# nvidia runtime が効いているか確認
sudo docker run --rm --runtime nvidia ubuntu nvidia-smi

# daemon.json を確認
cat /etc/docker/daemon.json
sudo systemctl restart docker
```

### ❌ autotag が失敗する

```bash
# jetson-containers が正しくインストールされているか確認
which autotag
ls ~/.local/bin/autotag

# PATH を確認
echo $PATH

# 手動でPATH追加
export PATH="$HOME/.local/bin:$PATH"
autotag ollama
```

### ❌ `nvidia-container-runtime` が見つからない

```bash
sudo apt-get update
sudo apt-get install -y nvidia-container
which nvidia-container-runtime  # /usr/bin/nvidia-container-runtime が出ればOK
```

### ❌ API が応答しない (コンテナは Up なのに)

```bash
# コンテナ内で Ollama が起動中か確認
sudo docker exec ollama ps aux | grep ollama

# ポートフォワードを確認
sudo docker port ollama

# ポートが使用中か確認
ss -tlnp | grep 11434
```

---

## 設定の調整

### コンテキスト長を増やしたい

`OLLAMA_NUM_CTX=2048` はメモリ節約のためのデフォルト値。
コンテナを作り直して変更する:

```bash
sudo docker stop ollama && sudo docker rm ollama
IMAGE=$(autotag ollama)

sudo docker run -d \
  --name ollama \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e OLLAMA_FLASH_ATTENTION=1 \
  -e OLLAMA_MAX_LOADED_MODELS=1 \
  -e OLLAMA_KEEP_ALIVE=5m \
  -e OLLAMA_NUM_CTX=4096 \   # 2048 → 4096 に変更
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v "$HOME/.ollama/models:/data/models/ollama/models" \
  -p 127.0.0.1:11434:11434 \
  --restart unless-stopped \
  "$IMAGE" \
  /bin/sh -c '/start_ollama; tail -f /data/logs/ollama.log'
```

### LAN 内の別マシンからアクセスする

`-p 127.0.0.1:11434:11434` を `-p 11434:11434` に変更してコンテナを作り直す。

別マシンからは `http://<jetson-ip>:11434` でアクセスできる。

---

## 関連ドキュメント

- `docs/quickstart.md` — Ollama 起動 & テストの最短手順
- `docs/api_usage.md` — OpenAI 互換 API の詳細
- `docs/troubleshooting.md` — その他のトラブルシューティング
- `models/model_list.md` — 推奨モデル全一覧
