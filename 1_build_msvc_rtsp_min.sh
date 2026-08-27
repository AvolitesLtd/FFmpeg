#!/bin/bash
set -euo pipefail

# Minimal MSVC shared build:
# H.264 decode (software + D3D11VA/DXVA2) + RTSP/RTP + the avfilter/swscale
# graph PhantomMedia uses (buffer/buffersink/format/scale/hwdownload).
# In-tree configure: FFmpeg rejects out-of-tree when the source path has a space
# (this tree lives under "Source Code"). Install prefix is still separate from
# the full Prism build. Prefer build_msvc_rtsp_min.bat from cmd.

if ! command -v clang-cl >/dev/null 2>&1; then
  export PATH="/c/Program Files/LLVM/bin:$PATH"
fi

if ! command -v cl >/dev/null 2>&1; then
  echo "cl.exe not found. Run build_msvc_rtsp_min.bat, or start MSYS2 from an x64 Native Tools prompt."
  exit 1
fi
if ! command -v clang-cl >/dev/null 2>&1; then
  echo "clang-cl not found. Add C:/Program Files/LLVM/bin to PATH."
  exit 1
fi
if ! command -v nasm >/dev/null 2>&1; then
  echo "nasm not found. In MSYS2: pacman -S nasm"
  exit 1
fi

ROOT="$(pwd)"
PREFIX="$ROOT/build/install-rtsp-min"
FFMPEG_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
BUILD_NAME="ffmpeg-${FFMPEG_VERSION}-win64-shared-rtsp-min"
JOBS=$(nproc 2>/dev/null || echo 8)

echo "==> tools"
echo "    pwd:      $ROOT"
echo "    cl:       $(command -v cl)"
echo "    clang-cl: $(command -v clang-cl)"
echo "    nasm:     $(command -v nasm)"
echo "    make:     $(command -v make)"
echo "    jobs:     $JOBS"
echo "    prefix:   $PREFIX"

mkdir -p "$PREFIX"

# Do not inherit encoder/zlib INCLUDE/LIB from a previous full MSVC build in this shell.
# --disable-autodetect then explicit d3d11va/dxva2 is the rest of that fence.
export INCLUDE="${INCLUDE:-}"
export LIB="${LIB:-}"
unset PKG_CONFIG_PATH || true

CONFIG_OPTS=(
  --toolchain=msvc
  --arch=x86_64
  --target-os=win64
  --cc=clang-cl
  --cxx=clang-cl
  --enable-debug
  --disable-optimizations
  --disable-stripping
  --enable-shared
  --disable-static
  --enable-w32threads
  --disable-autodetect
  --disable-everything
  --disable-doc
  --disable-ffplay
  --disable-ffprobe
  --enable-network
  --enable-d3d11va
  --enable-dxva2
  --enable-decoder=h264
  --enable-parser=h264
  --enable-bsf=h264_mp4toannexb,extract_extradata
  --enable-demuxer=rtsp,rtp,sdp,h264
  --enable-protocol=file,tcp,udp,rtp,http
  --enable-hwaccel=h264_d3d11va,h264_d3d11va2,h264_dxva2
  --enable-filter=format,scale,hwdownload,hwupload,hwmap,transpose,hflip,vflip,rotate,aformat,anull,null
  --prefix="$PREFIX"
)

echo "==> configure (can take several minutes before the first line)"
./configure "${CONFIG_OPTS[@]}"

fail_missing() { echo "ERROR: $1"; exit 1; }
CFG="$ROOT/config.h"
COMP="$ROOT/config_components.h"

[[ -f "$CFG" && -f "$COMP" ]] || fail_missing "configure did not write config.h / config_components.h"

if grep -q "^#define CONFIG_GPL 1" "$CFG"; then
  fail_missing "CONFIG_GPL is on; this build must stay LGPL (no --enable-gpl / libx264)."
fi
if grep -q "^#define CONFIG_LIBX264 1" "$CFG"; then
  fail_missing "libx264 was enabled; drop --enable-libx264 to keep LGPL."
fi
if grep -q "^#define CONFIG_HEVC_DECODER 1" "$COMP"; then
  fail_missing "HEVC decoder was enabled; this profile is H.264 only."
fi
if grep -q "^#define CONFIG_PNG_DECODER 1" "$COMP"; then
  fail_missing "PNG decoder was enabled; this profile should not pull zlib/image codecs."
fi
if grep -q "^#define CONFIG_H264_MF_ENCODER 1" "$COMP"; then
  fail_missing "h264_mf encoder was enabled; this profile is decode-only."
fi

grep -q "^#define CONFIG_NETWORK 1" "$CFG" || fail_missing "network was not enabled."
grep -q "^#define CONFIG_D3D11VA 1" "$CFG" || fail_missing "d3d11va was not enabled."
grep -q "^#define CONFIG_DXVA2 1" "$CFG" || fail_missing "dxva2 was not enabled."
grep -q "^#define CONFIG_H264_DECODER 1" "$COMP" || fail_missing "h264 decoder was not enabled."
grep -q "^#define CONFIG_H264_PARSER 1" "$COMP" || fail_missing "h264 parser was not enabled."
grep -q "^#define CONFIG_RTSP_DEMUXER 1" "$COMP" || fail_missing "rtsp demuxer was not enabled."
grep -q "^#define CONFIG_RTP_DEMUXER 1" "$COMP" || fail_missing "rtp demuxer was not enabled."
grep -q "^#define CONFIG_TCP_PROTOCOL 1" "$COMP" || fail_missing "tcp protocol was not enabled."
grep -q "^#define CONFIG_UDP_PROTOCOL 1" "$COMP" || fail_missing "udp protocol was not enabled."
grep -q "^#define CONFIG_H264_D3D11VA_HWACCEL 1" "$COMP" || fail_missing "h264_d3d11va hwaccel was not enabled."
grep -q "^#define CONFIG_H264_D3D11VA2_HWACCEL 1" "$COMP" || fail_missing "h264_d3d11va2 hwaccel was not enabled."
grep -q "^#define CONFIG_H264_DXVA2_HWACCEL 1" "$COMP" || fail_missing "h264_dxva2 hwaccel was not enabled."
grep -q "^#define CONFIG_SCALE_FILTER 1" "$COMP" || fail_missing "scale filter was not enabled."
grep -q "^#define CONFIG_FORMAT_FILTER 1" "$COMP" || fail_missing "format filter was not enabled."
grep -q "^#define CONFIG_HWDOWNLOAD_FILTER 1" "$COMP" || fail_missing "hwdownload filter was not enabled."
# buffer/buffersink are always linked into libavfilter (not --enable-filter names).
grep -q "ff_vsrc_buffer" "$ROOT/libavfilter/filter_list.c" || fail_missing "vsrc buffer filter missing from filter_list.c."
grep -q "ff_vsink_buffer" "$ROOT/libavfilter/filter_list.c" || fail_missing "vsink buffersink filter missing from filter_list.c."

echo "==> H.264 + RTSP + D3D11VA min profile enabled (LGPL)"

echo "==> make clean"
make clean
echo "==> make -j$JOBS (this is the long step; compiler lines should scroll)"
make -j"$JOBS"
echo "==> make install"
make install

mkdir -p "$PREFIX/bin"
# Skip files already under either install prefix (find would otherwise copy onto itself).
find . \( -path "./build/install-rtsp-min" -o -path "./build/install" \) -prune -o -name "*.pdb" -print0 | while IFS= read -r -d '' pdb; do
  cp -f "$pdb" "$PREFIX/bin/" || true
done

FFMPEG_BIN="$PREFIX/bin/ffmpeg.exe"

cat > "$PREFIX/readme.txt" << EOF
Build: $BUILD_NAME

profile: RTSP / H.264 decode only (SynergyPreviewsReceiver)
license: LGPL v2.1+ (no --enable-gpl, no libx264)
install: $PREFIX (in-tree configure; does not overwrite build/install)

Not included: zlib/png, HEVC, encoders (h264_mf / NVENC / AMF / QSV).
avdevice.dll is still built (empty device list) so PhantomMedia's current import list loads.
This FFmpeg tree has no libpostproc.

Configuration:
$("$FFMPEG_BIN" -buildconf 2>/dev/null | tail -n +2)

H.264 decoders:
$("$FFMPEG_BIN" -hide_banner -decoders 2>/dev/null | grep -E "h264" || true)

H.264 hwaccels:
$("$FFMPEG_BIN" -hide_banner -hwaccels 2>/dev/null || true)

RTSP / RTP demuxers:
$("$FFMPEG_BIN" -hide_banner -demuxers 2>/dev/null | grep -E "rtsp|rtp|sdp" || true)

Player filters:
$("$FFMPEG_BIN" -hide_banner -filters 2>/dev/null | grep -E "buffer|scale|format|hwdownload|transpose|hflip|vflip|rotate" || true)

Verify:
  ffmpeg -hide_banner -decoders | findstr h264
  ffmpeg -hide_banner -demuxers | findstr rtsp
  ffmpeg -hide_banner -hwaccels
  ffmpeg -hide_banner -filters | findstr /i "buffer scale hwdownload"

Copyright (C) $(date +%Y) Avolites LTD

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.
EOF

cp -f "$ROOT/COPYING.LGPLv2.1" "$PREFIX/COPYING.LGPLv2.1" || true

echo "Done! readme.txt generated at $PREFIX/readme.txt"
echo "    DLLs: $PREFIX/bin/"
echo "    Sync into Prism (runtime only, does not replace the full FFmpeg tree):"
echo "      Dependencies\\FFmpeg\\sync_to_prism_rtsp_min.bat \"$PREFIX\""
