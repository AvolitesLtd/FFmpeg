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
  --prefix="$PREFIX"

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

Configuration:
$("$PREFIX/bin/ffmpeg.exe" -buildconf 2>/dev/null | tail -n +2)

Copyright (C) $(date +%Y) Avolites LTD

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
EOF

echo "Done! readme.txt generated at $PREFIX/readme.txt"