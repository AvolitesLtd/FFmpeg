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

# Paths with spaces (D:\Source Code\...) cannot go in --extra-cflags/-ldflags:
# configure word-splits them and clang-cl treats "Code/..." as another source file.
# MSVC INCLUDE/LIB are semicolon-separated and accept spaces (same as vcvars).
if command -v cygpath >/dev/null 2>&1; then
  ZLIB_INC_WIN="$(cygpath -w "$ZLIB_PREFIX/include")"
  ZLIB_LIB_WIN="$(cygpath -w "$ZLIB_PREFIX/lib")"
else
  ZLIB_INC_WIN="$ZLIB_PREFIX/include"
  ZLIB_LIB_WIN="$ZLIB_PREFIX/lib"
fi
export INCLUDE="${ZLIB_INC_WIN}${INCLUDE:+;$INCLUDE}"
export LIB="${ZLIB_LIB_WIN}${LIB:+;$LIB}"
echo "    INCLUDE += $ZLIB_INC_WIN"
echo "    LIB     += $ZLIB_LIB_WIN"

echo "==> configure (can take several minutes before the first line)"
./configure \
  --toolchain=msvc \
  --arch=x86_64 \
  --target-os=win64 \
  --cc=clang-cl \
  --cxx=clang-cl \
  --enable-debug \
  --disable-optimizations \
  --disable-stripping \
  --enable-shared \
  --disable-static \
  --enable-zlib \
  --prefix="$PREFIX"

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

echo "==> make clean"
make clean
echo "==> make -j$JOBS (this is the long step; compiler lines should scroll)"
make -j"$JOBS"
echo "==> make install"
make install

mkdir -p "$PREFIX/bin"
find . -name "*.pdb" -exec cp {} "$PREFIX/bin/" \;

# generate readme
cat > "$PREFIX/readme.txt" << EOF
Build: $BUILD_NAME

zlib: $ZLIB_PREFIX (static zlib.lib, enables png/apng/exr and other inflate codecs)

Configuration:
$("$PREFIX/bin/ffmpeg.exe" -buildconf 2>/dev/null | tail -n +2)

Enabled image-related decoders:
$("$PREFIX/bin/ffmpeg.exe" -hide_banner -decoders 2>/dev/null | grep -E "png|apng|exr|tiff|mjpeg|jpeg|bmp|webp|gif|dpx|targa" || true)

Verify PNG:
  ffmpeg -hide_banner -decoders | findstr png
  ffmpeg -i frame_%04d.png -f null -

Copyright (C) $(date +%Y) Avolites LTD

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
EOF

echo "Done! readme.txt generated at $PREFIX/readme.txt"