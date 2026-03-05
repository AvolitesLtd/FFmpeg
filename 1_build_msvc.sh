#!/bin/bash

PREFIX="$(pwd)/build/install"
FFMPEG_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
BUILD_NAME="ffmpeg-${FFMPEG_VERSION}-win64-shared"

mkdir -p build/install

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
  --prefix=./build

make clean
make -j$(nproc)
make install

echo "Copying runtime DLLs..."
for dll in "$PREFIX/bin/"*.dll; do
  ldd "$dll" | grep '/mingw64/bin' | awk '{print $3}' | while read dep; do
    cp -n "$dep" "$PREFIX/bin/"
  done
done

# Copy PDBs to install bin dir
find . -name "*.pdb" -exec cp {} ./build/bin/ \;

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