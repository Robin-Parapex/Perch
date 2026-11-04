#!/usr/bin/env bash
# Generates the codec-matrix test library for Perch's playback decision table (docs/ARCHITECTURE.md).
# One folder, 30 s synthetic clips named after their container and codecs, plus README.txt.
# Usage: scripts/make-fixtures.sh [--no-4k] [--out <dir>] [--force]
# Needs ffmpeg and ffprobe (with libx264, libx265, libsvtav1, libvpx-vp9, libopus) and python3 (VOBSUB cue).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/fixtures/Perch Fixtures"
WITH_4K=1
FORCE=0
FFMPEG="${FFMPEG:-ffmpeg}"
FFPROBE="${FFPROBE:-ffprobe}"
[ -x /opt/homebrew/bin/ffmpeg ] && FFMPEG=/opt/homebrew/bin/ffmpeg
[ -x /opt/homebrew/bin/ffprobe ] && FFPROBE=/opt/homebrew/bin/ffprobe

while [ $# -gt 0 ]; do
  case "$1" in
    --no-4k) WITH_4K=0 ;;
    --force) FORCE=1 ;;
    --out) shift; OUT="${1:?--out needs a folder}" ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LOGS="$ROOT/build/fixtures/logs"
mkdir -p "$LOGS"

NAMES=(); EXPECT=(); DECISION=()
FAILED=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1  (log: ${2:-n/a})"; [ -n "${2:-}" ] && tail -n 8 "$2" | sed 's/^/      /'; FAILED=1; }

# make <file name> <expected codec names in stream order> <decision Perch should log> -- <ffmpeg args>
# Registers the clip, encodes it unless it exists (or --force), never leaves a partial file behind.
make() {
  local name="$1" expect="$2" decision="$3"; shift 3
  NAMES+=("$name"); EXPECT+=("$expect"); DECISION+=("$decision")
  local file="$OUT/$name" log="$LOGS/${name// /_}.log"
  if [ -s "$file" ] && [ "$FORCE" -eq 0 ]; then echo "SKIP  $name (exists)"; return 0; fi
  echo "MAKE  $name"
  if ! "$FFMPEG" -hide_banner -y -loglevel error -t 30 "$@" "$file" >"$log" 2>&1; then
    rm -f "$file"; fail "$name" "$log"
  fi
}

V1080="-f lavfi -i testsrc=size=1920x1080:rate=24:duration=30"   # testsrc burns in a running time counter
A2="-f lavfi -i sine=frequency=440:sample_rate=48000:duration=30"
PAN51="pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0"
X264="-c:v libx264 -preset ultrafast -pix_fmt yuv420p"
HDR10="colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400:hdr10=1:hdr10-opt=1:repeat-headers=1:log-level=error"
HDRTAGS="-color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc"

# --- Subtitle sources ---------------------------------------------------------------------------
SRT="$WORK/test.srt"; ASS="$WORK/test.ass"
{
  for i in 1 2 3 4 5; do
    s=$(( i * 5 )); printf '%d\n00:00:%02d,000 --> 00:00:%02d,000\nPerch subtitle test %d\n\n' "$i" "$s" "$((s + 3))" "$i"
  done
} > "$SRT"
{
  printf '[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\n\n[V4+ Styles]\n'
  printf 'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n'
  printf 'Style: Default,Arial,54,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,10,10,40,1\n\n[Events]\n'
  printf 'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
  for i in 1 2 3 4 5; do
    s=$(( i * 5 )); printf 'Dialogue: 0,0:00:%02d.00,0:00:%02d.00,Default,,0,0,0,,{\\i1}Perch ASS styled subtitle %d\n' "$s" "$((s + 3))" "$i"
  done
} > "$ASS"

# ffmpeg cannot encode PGS, or turn text into bitmaps, so the image subtitle is a hand-built VOBSUB
# (idx/sub pair holding three rectangle cues). It is a real DVD bitmap track, not real PGS.
python3 -I - "$WORK/vob" <<'PY'
import struct, sys
base = sys.argv[1]
W, H, X1, Y1, BW, BH = 1280, 720, 540, 600, 200, 40
def line(): return struct.pack(">HH", 0x0191, 0x0002)  # 100 px colour 1, rest colour 2, byte aligned
top = line() * (BH // 2); bot = line() * (BH // 2)
def cue(delay=264):
    off = 4 + len(top) + len(bot)
    seq1_len = 1 + 3 + 3 + 7 + 5 + 1
    seq2 = off + 4 + seq1_len
    c = struct.pack(">HH", 0, seq2) + b"\x01" + b"\x03\x02\x10" + b"\x04\x0f\xf0"
    c += b"\x05" + struct.pack(">I", (X1 << 12 | X1 + BW - 1) << 8 | 0)[0:3] if False else b""
    x = ((X1 << 12) | (X1 + BW - 1)).to_bytes(3, "big"); y = ((Y1 << 12) | (Y1 + BH - 1)).to_bytes(3, "big")
    c = struct.pack(">HH", 0, seq2) + b"\x01\x03\x02\x10\x04\x0f\xf0\x05" + x + y + b"\x06" + struct.pack(">HH", 4, 4 + len(top)) + b"\xff"
    c += struct.pack(">HH", delay, seq2) + b"\x02\xff"
    body = top + bot + c
    return struct.pack(">HH", 4 + len(body), off) + body
def pts(t):
    p = int(t * 90000)
    return bytes([0x21 | ((p >> 30) & 7) << 1, (p >> 22) & 255, ((p >> 15) & 127) << 1 | 1, (p >> 7) & 255, (p & 127) << 1 | 1])
sub = bytearray(); idx = []
for t in (2, 12, 22):
    spu = cue(); idx.append((t, len(sub)))
    sub += bytes.fromhex("000001BA440004000401018 9C3F8".replace(" ", ""))
    sub += b"\x00\x00\x01\xbd" + struct.pack(">H", 3 + 5 + 1 + len(spu)) + b"\x81\x80\x05" + pts(t) + b"\x20" + spu
open(base + ".sub", "wb").write(sub)
pal = ",".join(["000000", "ffe000", "202020"] + ["000000"] * 13)
with open(base + ".idx", "w") as f:
    f.write("# VobSub index file, v7 (do not modify this line!)\nsize: %dx%d\npalette: %s\n\nid: en, index: 0\n" % (W, H, pal))
    for t, pos in idx: f.write("timestamp: 00:00:%02d:000, filepos: %09x\n" % (t, pos))
PY

# --- Clips --------------------------------------------------------------------------------------
# shellcheck disable=SC2086  # the *-args variables are deliberately word-split
make "01 MP4 H264 AAC 1080p.mp4" "h264,aac" "direct play" \
  $V1080 $A2 $X264 -c:a aac -b:a 160k -movflags +faststart
make "02 MP4 HEVC SDR AAC 1080p.mp4" "hevc,aac" "direct play" \
  $V1080 $A2 -c:v libx265 -preset ultrafast -pix_fmt yuv420p -tag:v hvc1 -x265-params log-level=error -c:a aac -b:a 160k -movflags +faststart
make "03 MKV HEVC HDR10 EAC3 1080p.mkv" "hevc,eac3" "direct stream (MKV container; HDR10 kept, EAC3 passed through)" \
  $V1080 $A2 -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le -x265-params "$HDR10" $HDRTAGS -c:a eac3 -b:a 256k
make "04 MKV H264 AC3 51.mkv" "h264,ac3" "direct stream (MKV container; AC3 5.1 passed through)" \
  $V1080 $A2 $X264 -af "$PAN51" -c:a ac3 -b:a 448k
make "05 MKV H264 EAC3 51.mkv" "h264,eac3" "direct stream (MKV container; EAC3 5.1 passed through)" \
  $V1080 $A2 $X264 -af "$PAN51" -c:a eac3 -b:a 640k
make "06 MKV H264 TrueHD 51.mkv" "h264,truehd" "audio transcode (TrueHD to EAC3 5.1, video direct stream)" \
  $V1080 $A2 $X264 -af "$PAN51" -c:a truehd -strict -2
make "07 MKV H264 DTS 51.mkv" "h264,dts" "audio transcode (DTS to EAC3 5.1, video direct stream)" \
  $V1080 $A2 $X264 -af "$PAN51" -c:a dca -strict -2 -b:a 1509k
make "08 MKV H264 FLAC.mkv" "h264,flac" "audio transcode (FLAC to EAC3, video direct stream)" \
  $V1080 $A2 $X264 -c:a flac
make "09 MKV H264 SRT.mkv" "h264,aac,subrip" "direct stream (SRT converted to WebVTT in HLS)" \
  $V1080 $A2 -i "$SRT" -map 0:v -map 1:a -map 2:s $X264 -c:a aac -b:a 160k -c:s srt
make "10 MKV H264 ASS.mkv" "h264,aac,ass" "direct stream (ASS converted to WebVTT, styling lost)" \
  $V1080 $A2 -i "$ASS" -map 0:v -map 1:a -map 2:s $X264 -c:a aac -b:a 160k -c:s ass
make "11 MKV H264 VOBSUB image subtitle.mkv" "h264,aac,dvd_subtitle" "direct stream with subtitle off; transcode with burn-in if the image subtitle is selected (warn: needs re-encoding)" \
  $V1080 $A2 -i "$WORK/vob.idx" -map 0:v -map 1:a -map 2:s $X264 -c:a aac -b:a 160k -c:s copy
make "12 MKV AV1 AAC 1080p.mkv" "av1,aac" "transcode (AV1 has no hardware decode)" \
  $V1080 $A2 -c:v libsvtav1 -preset 12 -pix_fmt yuv420p -c:a aac -b:a 160k
make "13 WEBM VP9 Opus 1080p.webm" "vp9,opus" "transcode (VP9 video; Opus audio)" \
  $V1080 $A2 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -pix_fmt yuv420p -b:v 3M -c:a libopus -b:a 128k
make "14 TS MPEG2 4x3 SD AC3.ts" "mpeg2video,ac3" "transcode (MPEG-2 video; TS container)" \
  -f lavfi -i "testsrc=size=720x576:rate=25:duration=30" $A2 -vf "setsar=16/15,setdar=4/3" \
  -c:v mpeg2video -b:v 4M -pix_fmt yuv420p -c:a ac3 -b:a 192k -f mpegts
make "15 MP4 H264 AAC SRT sidecar.mp4" "h264,aac" "direct play with no subtitle; direct stream when the sidecar SRT is selected" \
  $V1080 $A2 $X264 -c:a aac -b:a 160k -movflags +faststart
cp "$SRT" "$OUT/15 MP4 H264 AAC SRT sidecar.en.srt"
if [ "$WITH_4K" -eq 1 ]; then
  make "16 MKV HEVC HDR10 EAC3 4K 80Mbit.mkv" "hevc,eac3" "direct stream (MKV container; 4K HDR10 at about 80 Mbit/s, check no downscale)" \
    -f lavfi -i "testsrc=size=3840x2160:rate=24:duration=30" $A2 -vf "noise=alls=40:allf=t+u,format=yuv420p10le" \
    -c:v libx265 -preset ultrafast -b:v 80M -maxrate 80M -bufsize 160M \
    -x265-params "$HDR10:vbv-maxrate=80000:vbv-bufsize=160000" $HDRTAGS -c:a eac3 -b:a 256k
fi

# --- README -------------------------------------------------------------------------------------
{
  echo "Perch codec-matrix fixtures. Each clip is 30 s of synthetic video with a running time counter and a 440 Hz tone."
  echo "Decision Perch should log for each file (docs/ARCHITECTURE.md, playback decision table):"
  echo
  for i in "${!NAMES[@]}"; do echo "${NAMES[$i]}: ${DECISION[$i]}"; done
  echo "15 MP4 H264 AAC SRT sidecar.en.srt: the sidecar subtitle for file 15."
  echo
  echo "Not synthesised (ffmpeg cannot make these honestly): Dolby Vision profile 5, 7 and 8.1, DTS:X,"
  echo "Atmos / EAC3-JOC, real PGS. These are covered by unit tests on metadata fixtures only."
  echo "File 11 uses a hand-built VOBSUB bitmap track as the stand-in image subtitle."
} > "$OUT/README.txt"

# --- Verify with ffprobe ------------------------------------------------------------------------
for i in "${!NAMES[@]}"; do
  f="$OUT/${NAMES[$i]}"
  [ -s "$f" ] || continue
  got="$("$FFPROBE" -v error -show_entries stream=index,codec_name -of csv=p=0 "$f" | awk -F, 'NF>=2 && !seen[$1]++ {print $2}' | paste -sd, -)"
  if [ "$got" = "${EXPECT[$i]}" ]; then pass "${NAMES[$i]} [$got]"; else fail "${NAMES[$i]} expected ${EXPECT[$i]}, got $got"; fi
done
# HDR10 tags: the MKV container header can read "unknown", so check the first decoded frame (the bitstream).
for f in "$OUT"/03\ *.mkv "$OUT"/16\ *.mkv; do
  [ -s "$f" ] || continue
  t="$("$FFPROBE" -v error -select_streams v -read_intervals "%+#1" -show_frames -show_entries frame=color_transfer,color_primaries -of csv=p=0 "$f" | head -n 1 | cut -d, -f1,2)"
  if [ "$t" = "bt2020,smpte2084" ]; then pass "$(basename "$f") HDR10 tags [$t]"; else fail "$(basename "$f") HDR10 tags, got $t"; fi
done
du -sh "$OUT" | awk '{print "Folder size: " $1}'
exit "$FAILED"
