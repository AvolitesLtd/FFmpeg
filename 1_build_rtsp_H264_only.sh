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
  --enable-w32threads \
  --disable-doc \
  --disable-everything \
  --enable-decoder=h264 \
  --enable-decoder=h264_cuvid \
  --enable-hwaccel=h264_d3d11va \
  --enable-hwaccel=h264_d3d11va2 \
  --enable-hwaccel=h264_dxva2 \
  --enable-hwaccel=h264_nvdec \
  --enable-demuxer=rtsp \
  --enable-demuxer=sdp \
  --enable-demuxer=rtp \
  --enable-parser=h264 \
  --enable-bsf=h264_mp4toannexb \
  --enable-protocol=rtsp \
  --enable-protocol=rtp \
  --enable-protocol=tcp \
  --enable-protocol=udp \
  --enable-protocol=udplite \
  --enable-cuvid \
  --enable-d3d11va \
  --enable-dxva2 \
  --enable-ffnvcodec \
  --enable-nvdec

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