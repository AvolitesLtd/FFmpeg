#!/bin/bash
set -euo pipefail

# Steps 3–4: clang-cl on PATH, then configure/build/install MSVC shared DLLs.
# Prefer build_msvc.bat from cmd so vcvars64 + MSYS2 inherit are set (steps 1–2).

if ! command -v clang-cl >/dev/null 2>&1; then
  export PATH="/c/Program Files/LLVM/bin:$PATH"
fi

if ! command -v cl >/dev/null 2>&1; then
  echo "cl.exe not found. Run build_msvc.bat, or start MSYS2 from an x64 Native Tools prompt."
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

PREFIX="$(pwd)/build/install"
ZLIB_PREFIX="$(pwd)/build/zlib"
FFMPEG_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
BUILD_NAME="ffmpeg-${FFMPEG_VERSION}-win64-shared"
JOBS=$(nproc 2>/dev/null || echo 8)

echo "==> tools"
echo "    pwd:      $(pwd)"
echo "    cl:       $(command -v cl)"
echo "    clang-cl: $(command -v clang-cl)"
echo "    nasm:     $(command -v nasm)"
echo "    make:     $(command -v make)"
echo "    jobs:     $JOBS"
echo "    prefix:   $PREFIX"

mkdir -p "$PREFIX"

echo "==> zlib (required for png/apng/exr and other inflate decoders)"
./0_build_zlib_msvc.sh

echo "==> H.264 encoders deps (libx264, AMF, NVENC, QSV)"
./0_build_encoder_deps_msvc.sh
ENC_PREFIX="$(tr -d '\r' < build/encoder_deps_prefix.txt)"
if [[ -z "$ENC_PREFIX" ]]; then
  echo "ERROR: encoder deps prefix missing (build/encoder_deps_prefix.txt)"
  exit 1
fi

# Paths with spaces (D:\Source Code\...) cannot go in --extra-cflags/-ldflags:
# configure word-splits them and clang-cl treats "Code/..." as another source file.
# MSVC INCLUDE/LIB are semicolon-separated and accept spaces (same as vcvars).
# Encoder deps are installed to a space-free prefix so pkg-config stays valid.
if command -v cygpath >/dev/null 2>&1; then
  ZLIB_INC_WIN="$(cygpath -w "$ZLIB_PREFIX/include")"
  ZLIB_LIB_WIN="$(cygpath -w "$ZLIB_PREFIX/lib")"
  ENC_INC_WIN="$(cygpath -w "$ENC_PREFIX/include")"
  ENC_LIB_WIN="$(cygpath -w "$ENC_PREFIX/lib")"
  ENC_PC_UNIX="$(cygpath -u "$ENC_PREFIX/lib/pkgconfig")"
else
  ZLIB_INC_WIN="$ZLIB_PREFIX/include"
  ZLIB_LIB_WIN="$ZLIB_PREFIX/lib"
  ENC_INC_WIN="$ENC_PREFIX/include"
  ENC_LIB_WIN="$ENC_PREFIX/lib"
  ENC_PC_UNIX="$ENC_PREFIX/lib/pkgconfig"
fi
export INCLUDE="${ENC_INC_WIN};${ZLIB_INC_WIN}${INCLUDE:+;$INCLUDE}"
export LIB="${ENC_LIB_WIN};${ZLIB_LIB_WIN}${LIB:+;$LIB}"
export PKG_CONFIG_PATH="${ENC_PC_UNIX}${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
echo "    INCLUDE += $ENC_INC_WIN"
echo "    INCLUDE += $ZLIB_INC_WIN"
echo "    LIB     += $ENC_LIB_WIN"
echo "    LIB     += $ZLIB_LIB_WIN"
echo "    PKG_CONFIG_PATH=$PKG_CONFIG_PATH"

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "ERROR: pkg-config not found. In MSYS2: pacman -S pkg-config"
  exit 1
fi

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
  --enable-gpl
  --enable-zlib
  --enable-libx264
  --enable-amf
  --enable-ffnvcodec
  --enable-nvenc
  --prefix="$PREFIX"
)
if [[ -f "$ENC_PREFIX/lib/pkgconfig/vpl.pc" ]]; then
  CONFIG_OPTS+=(--enable-libvpl)
  echo "    libvpl: enabled"
else
  echo "    libvpl: skipped (vpl.pc not found)"
fi

echo "==> configure (can take several minutes before the first line)"
./configure "${CONFIG_OPTS[@]}"

if ! grep -q "^#define CONFIG_ZLIB 1" config.h; then
  echo "ERROR: zlib was not detected. PNG decoder will stay disabled."
  echo "       Check ffbuild/config.log for zlib.h / zlib.lib."
  exit 1
fi
# Individual codecs live in config_components.h (not config.h) on current FFmpeg.
if ! grep -q "^#define CONFIG_PNG_DECODER 1" config_components.h; then
  echo "ERROR: PNG decoder was not enabled (needs zlib inflate_wrapper)."
  exit 1
fi
echo "==> zlib and png decoder enabled"

fail_missing() { echo "ERROR: $1"; exit 1; }
grep -q "^#define CONFIG_LIBX264 1" config.h || fail_missing "libx264 was not enabled (needed for H.264 software encode)."
grep -q "^#define CONFIG_LIBX264_ENCODER 1" config_components.h || fail_missing "libx264 encoder was not enabled."
grep -q "^#define CONFIG_H264_MF_ENCODER 1" config_components.h || fail_missing "h264_mf encoder was not enabled."
grep -q "^#define CONFIG_AMF 1" config.h || fail_missing "AMF was not enabled (h264_amf)."
grep -q "^#define CONFIG_H264_AMF_ENCODER 1" config_components.h || fail_missing "h264_amf encoder was not enabled."
grep -q "^#define CONFIG_NVENC 1" config.h || fail_missing "NVENC was not enabled."
grep -q "^#define CONFIG_H264_NVENC_ENCODER 1" config_components.h || fail_missing "h264_nvenc encoder was not enabled."
if [[ -f "$ENC_PREFIX/lib/pkgconfig/vpl.pc" ]]; then
  grep -q "^#define CONFIG_LIBVPL 1" config.h || fail_missing "libvpl was not enabled (h264_qsv)."
  grep -q "^#define CONFIG_H264_QSV_ENCODER 1" config_components.h || fail_missing "h264_qsv encoder was not enabled."
  QSV_NOTE=", h264_qsv"
else
  QSV_NOTE=""
fi
echo "==> H.264 encoders enabled (libx264, h264_mf, h264_amf, h264_nvenc${QSV_NOTE})"

echo "==> make clean"
make clean
echo "==> make -j$JOBS (this is the long step; compiler lines should scroll)"
make -j"$JOBS"
echo "==> make install"
make install

mkdir -p "$PREFIX/bin"
# Skip files already under the install prefix (find would otherwise try to copy them onto themselves).
find . -path "./build/install" -prune -o -name "*.pdb" -print0 | while IFS= read -r -d '' pdb; do
  cp -f "$pdb" "$PREFIX/bin/" || true
done
# oneVPL dispatcher (installed as libvpl.dll)
if compgen -G "$ENC_PREFIX/bin/"*vpl*.dll > /dev/null; then
  cp -f "$ENC_PREFIX"/bin/*vpl*.dll "$PREFIX/bin/" || true
fi

# generate readme
cat > "$PREFIX/readme.txt" << EOF
Build: $BUILD_NAME

zlib: $ZLIB_PREFIX (static zlib.lib, enables png/apng/exr and other inflate codecs)
encoder deps: $ENC_PREFIX (libx264, AMF, ffnvcodec/NVENC, libvpl/QSV)

Configuration:
$("$PREFIX/bin/ffmpeg.exe" -buildconf 2>/dev/null | tail -n +2)

H.264 encoders:
$("$PREFIX/bin/ffmpeg.exe" -hide_banner -encoders 2>/dev/null | grep -E "libx264|h264_mf|h264_nvenc|h264_amf|h264_qsv" || true)

Enabled image-related decoders:
$("$PREFIX/bin/ffmpeg.exe" -hide_banner -decoders 2>/dev/null | grep -E "png|apng|exr|tiff|mjpeg|jpeg|bmp|webp|gif|dpx|targa" || true)

Verify PNG:
  ffmpeg -hide_banner -decoders | findstr png
  ffmpeg -i frame_%04d.png -f null -

Verify H.264 encoders:
  ffmpeg -hide_banner -encoders | findstr "libx264 h264_mf h264_nvenc h264_amf h264_qsv"

Copyright (C) $(date +%Y) Avolites LTD

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
EOF

echo "Done! readme.txt generated at $PREFIX/readme.txt"