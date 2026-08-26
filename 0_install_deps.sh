#!/bin/bash

echo "Installing build tools..."
pacman -S --needed --noconfirm \
  mingw-w64-x86_64-toolchain \
  make \
  nasm \
  yasm \
  mingw-w64-x86_64-pkg-config \
  diffutils

echo "Installing FFmpeg dependencies..."
pacman -S --needed --noconfirm \
  mingw-w64-x86_64-SDL2 \
  mingw-w64-x86_64-fontconfig \
  mingw-w64-x86_64-gnutls \
  mingw-w64-x86_64-libass \
  mingw-w64-x86_64-libbluray \
  mingw-w64-x86_64-freetype \
  mingw-w64-x86_64-lame \
  mingw-w64-x86_64-opencore-amr \
  mingw-w64-x86_64-openjpeg2 \
  mingw-w64-x86_64-opus \
  mingw-w64-x86_64-libsoxr \
  mingw-w64-x86_64-libtheora \
  mingw-w64-x86_64-twolame \
  mingw-w64-x86_64-libvpx \
  mingw-w64-x86_64-libwebp \
  mingw-w64-x86_64-libxml2 \
  mingw-w64-x86_64-zimg \
  mingw-w64-x86_64-xz \
  mingw-w64-x86_64-zlib \
  mingw-w64-x86_64-gmp \
  mingw-w64-x86_64-libvorbis \
  mingw-w64-x86_64-libmysofa \
  mingw-w64-x86_64-speex \
  mingw-w64-x86_64-aom \
  mingw-w64-x86_64-libvpl \
  mingw-w64-x86_64-onevpl \
  mingw-w64-x86_64-shine \
  mingw-w64-x86_64-snappy \
  mingw-w64-x86_64-vo-amrwbenc \
  mingw-w64-x86_64-ffnvcodec-headers \
  mingw-w64-x86_64-amf-headers 

echo "All dependencies installed!"