# トラブルシューティング

## Ollama (Docker コンテナ)

### ❌ コンテナが起動しない

```bash
# ログ確認
sudo docker logs ollama

# コンテナの状態
sudo docker ps -a --filter name=ollama

# nvidia runtime が効いているか確認
sudo docker run --rm --runtime nvidia ubuntu nvidia-smi

# daemon.json 確認
cat /etc/docker/daemon.json
sudo systemctl restart docker
```

### ❌ API が応答しない

```bash
# コンテナが実行中か確認
sudo docker ps --filter name=ollama

# ポート確認
ss -tlnp | grep 11434

# コンテナ内 Ollama プロセス確認
sudo docker exec ollama ps aux | grep ollama

# 再起動
sudo docker stop ollama
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
sudo docker start ollama
```

### ❌ モデルのロードが遅い / OOMで落ちる

```bash
# MemFree を確認 (NvMap に必要)
grep MemFree /proc/meminfo
# → 2GB 以上ないと OOM になる

# ページキャッシュを解放してから再起動
sudo docker stop ollama
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
grep MemFree /proc/meminfo   # 3GB 以上あれば OK
sudo docker start ollama

# より小さいモデルに切り替え
# 7B → 3B, 3B → 2B
```

**原因**: 8GB共有メモリの実効使用可能量は~5〜6GB。NvMap は MemFree のみ使用可能。

### ❌ GPU が使われていない

```bash
# tegrastats で GR3D_FREQ を確認
tegrastats --interval 1000
# GR3D_FREQ が 0% = GPU 未使用 (CPU推論になっている)

# ロード中モデルの確認 (API)
curl -s http://localhost:11434/api/ps | python3 -m json.tool
# size_vram が 0 なら GPU に乗っていない

# 対処: drop_caches → 再起動
sudo docker stop ollama
sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
sudo docker start ollama
```

---

## autotag / jetson-containers

### ❌ `autotag: command not found`

```bash
# PATH を確認
ls ~/.local/bin/autotag

# PATH 追加
export PATH="$HOME/.local/bin:$PATH"

# それでも見つからない場合は再インストール
bash ~/jetson-containers/install.sh
```

### ❌ autotag がイメージを解決できない

```bash
# JetPack バージョン確認
cat /etc/nv_tegra_release

# autotag のデバッグ出力
autotag ollama 2>&1

# jetson-containers を最新に更新
cd ~/jetson-containers && git pull
```

---

## モデルダウンロード

### ❌ pull が途中で止まる / 失敗する

```bash
# API経由で再送 (Ollama が再開点から継続)
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "qwen2.5:7b"}'

# 進捗の確認
# 上記コマンドはNDJSONストリームで進捗を返す
```

### ❌ HuggingFace ダウンロードが遅い / 途中で落ちる

```bash
# レジューム対応ダウンロード
pip3 install huggingface_hub
huggingface-cli download \
  bartowski/Qwen2.5-7B-Instruct-GGUF \
  Qwen2.5-7B-Instruct-Q4_K_M.gguf \
  --local-dir ~/.ollama/models/imports \
  --resume-download
```

---

## Jetson固有

### tegrastats の読み方

```
RAM 3500/7993MB (lfb 1x2MB) SWAP 0/0MB
CPU [45%@1510,12%@1510,...] EMC_FREQ 0%
GR3D_FREQ 98%  # GPU使用率 (これが高いと良い)
```

### 電力モード確認

```bash
# 現在のモード
sudo nvpmodel -q

# MAXN (25W) に変更
sudo nvpmodel -m 0

# 設定一覧
sudo nvpmodel --list
```

### 温度が高い

```bash
# 温度確認
cat /sys/devices/virtual/thermal/thermal_zone*/temp

# ファンを最大に
sudo sh -c 'echo 255 > /sys/devices/platform/pwm-fan/hwmon/hwmon*/pwm1'
```

### vm.min_free_kbytes の確認

```bash
# 現在の設定確認
sysctl vm.min_free_kbytes
# → 2097152 (2GB) が設定されていればOK

# 設定ファイル確認
cat /etc/sysctl.d/99-ollama-jetson.conf
```
