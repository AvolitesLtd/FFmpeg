#!/bin/bash

PREFIX="$(pwd)/build/install"
FFMPEG_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
BUILD_NAME="ffmpeg-${FFMPEG_VERSION}-win64-shared"

mkdir -p build/install

./configure \
  --prefix="$PREFIX" \
  --target-os=mingw32 \
  --arch=x86_64 \
  --enable-shared \
  --disable-static \
  --enable-gpl \
  --enable-version3 \
  --enable-w32threads \
  --disable-doc \
  --enable-sdl2 \
  --enable-fontconfig \
  --enable-gnutls \
  --enable-iconv \
  --enable-libass \
  --enable-libbluray \
  --enable-libfreetype \
  --enable-libmp3lame \
  --enable-libopencore-amrnb \
  --enable-libopencore-amrwb \
  --enable-libopenjpeg \
  --enable-libopus \
  --enable-libshine \
  --enable-libsnappy \
  --enable-libsoxr \
  --enable-libtheora \
  --enable-libtwolame \
  --enable-libvpx \
  --enable-libwebp \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libxml2 \
  --enable-libzimg \
  --enable-lzma \
  --enable-zlib \
  --enable-gmp \
  --enable-libvidstab \
  --enable-libvorbis \
  --enable-libvo-amrwbenc \
  --enable-libmysofa \
  --enable-libspeex \
  --enable-libxvid \
  --enable-libaom \
  --enable-libvpl \
  --enable-amf \
  --enable-ffnvcodec \
  --enable-cuvid \
  --enable-d3d11va \
  --enable-nvenc \
  --enable-nvdec \
  --enable-dxva2

make clean
make -j$(nproc)
make install

echo "Copying runtime DLLs..."
for dll in "$PREFIX/bin/"*.dll; do
  ldd "$dll" | grep '/mingw64/bin' | awk '{print $3}' | while read dep; do
    cp -n "$dep" "$PREFIX/bin/"
  done
done

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