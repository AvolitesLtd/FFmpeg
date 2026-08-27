#!/bin/bash
# MSVC H.264 encoder deps: AMF, NVENC (ffnvcodec), QSV (libvpl).
# No libx264 — that would require --enable-gpl and turn the FFmpeg DLLs GPL.
# Installs to a path WITHOUT spaces so pkg-config flags survive FFmpeg configure.
set -euo pipefail

ROOT="$(pwd)"
SRC_ROOT="$ROOT/build/deps"
MARKER="$ROOT/build/encoder_deps_prefix.txt"

if [[ -n "${FFMPEG_MSVC_DEPS:-}" ]]; then
  PREFIX="$(cygpath -m "$FFMPEG_MSVC_DEPS")"
elif [[ -n "${LOCALAPPDATA:-}" ]]; then
  PREFIX="$(cygpath -m "$LOCALAPPDATA/ffmpeg-msvc-deps")"
else
  PREFIX="C:/ffmpeg-msvc-deps"
fi

PREFIX_MIXED="$(cygpath -m "$PREFIX" 2>/dev/null || echo "$PREFIX")"
PREFIX_UNIX="$(cygpath -u "$PREFIX" 2>/dev/null || echo "$PREFIX")"
PREFIX="$PREFIX_MIXED"

mkdir -p "$SRC_ROOT" "$PREFIX/include" "$PREFIX/lib/pkgconfig" "$PREFIX/bin"

win_prefix() { cygpath -m "$1"; }
unix_pc() { cygpath -u "$1"; }

echo "==> encoder deps prefix: $PREFIX (no spaces; used by pkg-config)"
echo "$PREFIX" > "$MARKER"

have_lib() { [[ -f "$PREFIX/lib/$1" || -f "$PREFIX/lib/lib$1" ]]; }

download_tar() {
  local url="$1" dest="$2"
  if [[ ! -f "$dest" ]]; then
    echo "    downloading $(basename "$dest")"
    curl -L --fail -o "$dest" "$url"
  fi
}

# GitHub archive extracts to <repo>-master/; unpack into dest (no mv — Windows locks).
fetch_github_tree() {
  local repo="$1" dest="$2"
  local name="${repo##*/}"
  if [[ -d "$dest/.git" || -f "$dest/configure" || -f "$dest/CMakeLists.txt" || -f "$dest/Makefile" ]]; then
    return 0
  fi
  rm -rf "$dest" "${dest}-master"
  mkdir -p "$dest"
  local archive="$SRC_ROOT/${name}-master.tar.gz"
  download_tar "https://github.com/${repo}/archive/refs/heads/master.tar.gz" "$archive"
  echo "    extracting $(basename "$archive")"
  tar --strip-components=1 -xf "$archive" -C "$dest"
}

# pkg-config under MSYS writes /c/Users/...; clang-cl needs C:/Users/...
rewrite_pc_prefix() {
  local pc="$1"
  [[ -f "$pc" ]] || return 0
  sed -i "s|^prefix=.*|prefix=${PREFIX}|" "$pc"
}

export MSYS2_ARG_CONV_EXCL='*'

echo "==> skipping x264 (keeps FFmpeg LGPL; software H.264 uses h264_mf)"

# ---------------------------------------------------------------------------
# AMF headers (h264_amf / hevc_amf)
# ---------------------------------------------------------------------------
if [[ -f "$PREFIX/include/AMF/core/Version.h" ]]; then
  echo "==> AMF headers already installed"
else
  echo "==> installing AMF headers"
  AMF_SRC="$SRC_ROOT/AMF"
  fetch_github_tree "GPUOpen-LibrariesAndSDKs/AMF" "$AMF_SRC"
  mkdir -p "$PREFIX/include/AMF"
  cp -R "$AMF_SRC/amf/public/include/." "$PREFIX/include/AMF/"
fi

# ---------------------------------------------------------------------------
# nv-codec-headers (NVENC / ffnvcodec)
# ---------------------------------------------------------------------------
if [[ -f "$PREFIX/lib/pkgconfig/ffnvcodec.pc" ]]; then
  echo "==> ffnvcodec already installed"
else
  echo "==> installing nv-codec-headers"
  NV_SRC="$SRC_ROOT/nv-codec-headers"
  fetch_github_tree "FFmpeg/nv-codec-headers" "$NV_SRC"
  make -C "$NV_SRC" install PREFIX="$PREFIX_UNIX"
  rewrite_pc_prefix "$PREFIX/lib/pkgconfig/ffnvcodec.pc"
fi

# ---------------------------------------------------------------------------
# libvpl (h264_qsv / hevc_qsv)
# ---------------------------------------------------------------------------
if [[ -f "$PREFIX/lib/pkgconfig/vpl.pc" ]]; then
  echo "==> libvpl already installed"
else
  echo "==> building libvpl"
  VPL_SRC="$SRC_ROOT/libvpl"
  fetch_github_tree "intel/libvpl" "$VPL_SRC"
  if ! command -v cmake >/dev/null 2>&1; then
    echo "WARNING: cmake not found; skipping libvpl (QSV). Install CMake or VS CMake tools."
  else
    # Windows cmake/nmake reject MSYS paths and break on spaces; build under PREFIX.
    VPL_SRC_WIN="$PREFIX/src/libvpl"
    VPL_BLD_WIN="$PREFIX/src/libvpl-build"
    if [[ ! -f "$VPL_SRC_WIN/CMakeLists.txt" ]]; then
      mkdir -p "$VPL_SRC_WIN"
      cp -a "$VPL_SRC/." "$VPL_SRC_WIN/"
    fi
    rm -rf "$VPL_BLD_WIN"
    mkdir -p "$VPL_BLD_WIN"
    VPL_S="$(cygpath -m "$VPL_SRC_WIN")"
    VPL_B="$(cygpath -m "$VPL_BLD_WIN")"
    echo "    cmake -S $VPL_S -B $VPL_B"
    cmake -S "$VPL_S" -B "$VPL_B" -G "NMake Makefiles" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=cl \
      -DCMAKE_CXX_COMPILER=cl \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL \
      -DBUILD_SHARED_LIBS=ON \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_TESTS=OFF \
      -DINSTALL_DEV=ON \
      -DINSTALL_EXAMPLES=OFF
    cmake --build "$VPL_B"
    cmake --install "$VPL_B"
    rewrite_pc_prefix "$PREFIX/lib/pkgconfig/vpl.pc"
    if [[ -f "$PREFIX/lib/libvpl.lib" && ! -f "$PREFIX/lib/vpl.lib" ]]; then
      cp -f "$PREFIX/lib/libvpl.lib" "$PREFIX/lib/vpl.lib"
    fi
  fi
fi

rewrite_pc_prefix "$PREFIX/lib/pkgconfig/ffnvcodec.pc"
rewrite_pc_prefix "$PREFIX/lib/pkgconfig/vpl.pc"

echo "==> encoder deps ready"
echo "    prefix: $PREFIX"
ls -1 "$PREFIX/lib/pkgconfig" 2>/dev/null || true
ls -1 "$PREFIX/lib"/*.lib 2>/dev/null || true
