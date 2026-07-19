#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
用法: transcode_h264.sh [-o|--original] <影片路徑> [開始時間]

  轉碼成 H.264 (libx264) + AAC，輸出 .mp4。
  來源寬度超過 1280 (720p) 時等比例縮小，否則維持原尺寸。

選項:
  -o, --original   把輸出存到「原始影片」旁的資料夾
                   (預設: 存到本腳本所在的資料夾)
  -h, --help       顯示此說明

參數:
  影片路徑          來源影片 (mkv、mp4 等)
  開始時間 (選填)   秒數 (如 90) 或 時:分:秒 (如 00:01:30)
USAGE
}

# --- 參數解析 ---
save_beside_original=0
positional=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--original) save_beside_original=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; while [ "$#" -gt 0 ]; do positional+=("$1"); shift; done ;;
    -*)            echo "未知選項: $1" >&2; usage; exit 1 ;;
    *)             positional+=("$1"); shift ;;
  esac
done

if [ "${#positional[@]}" -lt 1 ] || [ "${#positional[@]}" -gt 2 ]; then
  usage
  exit 1
fi

input="${positional[0]}"
start="${positional[1]:-}"   # 開始時間可省略

# --- 檔案存在檢查 ---
if [ ! -f "$input" ]; then
  echo "找不到檔案: $input" >&2
  exit 1
fi

# --- 決定輸出資料夾 ---
# 預設: 腳本所在資料夾; 加 -o/--original: 原始影片所在資料夾
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$save_beside_original" -eq 1 ]; then
  out_dir="$(cd "$(dirname "$input")" && pwd)"
  echo "輸出位置: 原始影片旁 (${out_dir})"
else
  out_dir="$script_dir"
  echo "輸出位置: 腳本所在資料夾 (${out_dir})"
fi

base="$(basename "$input")"
name="${base%.*}"
output="${out_dir}/${name}_h264.mp4"

# --- 避免覆蓋 ---
if [ -e "$output" ]; then
  echo "輸出檔已存在，不覆蓋: $output" >&2
  exit 1
fi

# --- 讀出來源寬度 (取第一條影像串流) ---
width="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width -of csv=p=0 "$input")"

if ! [[ "$width" =~ ^[0-9]+$ ]]; then
  echo "無法偵測影片寬度: $input" >&2
  exit 1
fi

# --- 縮放門檻 (寬 1280，手機串流甜蜜點 720p) ---
MAX_WIDTH=1280

scale_args=()
if [ "$width" -gt "$MAX_WIDTH" ]; then
  echo "來源寬度 ${width}px 超過 ${MAX_WIDTH}px，降到寬 ${MAX_WIDTH}"
  scale_args=(-vf "scale=${MAX_WIDTH}:-2")
else
  echo "來源寬度 ${width}px，不需縮放，繼續轉碼"
fi

# --- 開始時間 (放在 -i 之前，速度快且精準) ---
seek_args=()
if [ -n "$start" ]; then
  echo "從 ${start} 開始"
  seek_args=(-ss "$start")
fi

# 用 "${arr[@]+"${arr[@]}"}" 展開，空陣列在 set -u 下才不會報錯退出
ffmpeg "${seek_args[@]+"${seek_args[@]}"}" -i "$input" \
  "${scale_args[@]+"${scale_args[@]}"}" \
  -c:v libx264 -preset medium -crf 20 \
  -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  -movflags +faststart \
  "$output"

echo "完成: $output"