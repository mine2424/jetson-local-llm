# トラブルシューティング

## Ollama

### ❌ `ollama: command not found`

```bash
# インストール確認
which ollama
ls /usr/local/bin/ollama

# 再インストール
bash setup/01_install_ollama.sh
```

### ❌ モデルのロードが遅い / OOMで落ちる

```bash
# 現在のメモリ状況確認
free -h
tegrastats  # リアルタイム GPU/CPU/RAM モニタ

# 解決策: 軽量モデルに切り替え
ollama stop qwen2.5:7b
ollama run gemma2:2b  # まず動作確認
```

**原因**: 8GB共有メモリの実効使用可能量は~5〜6GB。大きいモデルはQ4量子化でも足りない場合あり。

### ❌ `Error: model requires more system memory`

```bash
# 電力モード確認（25W最大に設定）
sudo nvpmodel -m 0     # MAXN (25W)
sudo jetson_clocks     # クロック最大化

# それでも無理なら一段小さいモデルへ
# 7B → 3B, 3B → 1B
```

### ❌ Ollama APIが応答しない

```bash
# サービス状態確認
sudo systemctl status ollama

# ポート確認
ss -tlnp | grep 11434

# 再起動
sudo systemctl restart ollama

# ログ確認
journalctl -u ollama -n 50
```

---

## llama.cpp

### ❌ CUDA が使われていない (GPU: 0%)

```bash
# ビルド時にCUDA有効になってるか確認
ls ~/llama.cpp/build/bin/llama-cli
ldd ~/llama.cpp/build/bin/llama-cli | grep cuda

# -ngl フラグを確認 (省略するとCPUのみ)
llama-cli -m model.gguf -p "test" -ngl 999
```

### ❌ `CUDA error: out of memory`

```bash
# GPU layerを減らす
llama-cli -m model.gguf -p "test" -ngl 20  # 一部だけGPUに乗せる

# Ollamaが同時起動してたら止める
sudo systemctl stop ollama
```

---

## モデルダウンロード

### ❌ HuggingFace ダウンロードが遅い / 途中で落ちる

```bash
# レジューム対応ダウンロード
pip3 install huggingface_hub[cli]
huggingface-cli download \
  bartowski/Qwen2.5-7B-Instruct-GGUF \
  Qwen2.5-7B-Instruct-Q4_K_M.gguf \
  --local-dir ~/models \
  --resume-download
```

### ❌ `ollama pull` が途中で止まる

```bash
# Ollama自体がhttps接続をリトライしてくれる
# 単純に再実行
ollama pull qwen2.5:7b
# 再開点から継続される
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
