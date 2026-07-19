#!/usr/bin/env bash
set -euo pipefail

# 用法檢查
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "用法: $0 <影片路徑> [開始時間]" >&2
  echo "  開始時間格式: 秒數 (如 90) 或 時:分:秒 (如 00:01:30)" >&2
  exit 1
fi

input="$1"
start="${2:-}"   # 第二參數可省略

# 檔案存在檢查
if [ ! -f "$input" ]; then
  echo "找不到檔案: $input" >&2
  exit 1
fi

# 拆解路徑
dir="$(dirname "$input")"
base="$(basename "$input")"
name="${base%.*}"
output="${dir}/${name}_h264.mp4"

# 避免覆蓋
if [ -e "$output" ]; then
  echo "輸出檔已存在，不覆蓋: $output" >&2
  exit 1
fi

# 讀出來源寬度（取第一條影像串流）
width="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width -of csv=p=0 "$input")"

if ! [[ "$width" =~ ^[0-9]+$ ]]; then
  echo "無法偵測影片寬度: $input" >&2
  exit 1
fi

# 2K 門檻（寬 2560）
MAX_WIDTH=2560

# 組出縮放參數
scale_args=()
if [ "$width" -gt "$MAX_WIDTH" ]; then
  echo "來源寬度 ${width}px 超過 ${MAX_WIDTH}px，降回 2K"
  scale_args=(-vf "scale=${MAX_WIDTH}:-2")
else
  echo "來源寬度 ${width}px，不需縮放"
fi

# 組出開始時間參數（放在 -i 之前，速度快且精準）
seek_args=()
if [ -n "$start" ]; then
  echo "從 ${start} 開始"
  seek_args=(-ss "$start")
fi

ffmpeg "${seek_args[@]}" -i "$input" \
  "${scale_args[@]}" \
  -c:v libx264 -preset medium -crf 20 \
  -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  -movflags +faststart \
  "$output"

echo "完成: $output"