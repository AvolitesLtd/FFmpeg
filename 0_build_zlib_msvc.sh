#!/bin/bash
# Build a static MSVC zlib.lib for FFmpeg (PNG/APNG/EXR and other inflate codecs).
# Requires cl/clang-cl + lib.exe from vcvars (run via build_msvc.bat).
set -euo pipefail

ZLIB_VERSION=1.3.1
ROOT="$(pwd)"
DEPS="$ROOT/build/deps"
SRC="$DEPS/zlib-${ZLIB_VERSION}"
PREFIX="$ROOT/build/zlib"
ARCHIVE="$DEPS/zlib-${ZLIB_VERSION}.tar.gz"
URL="https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"

if ! command -v clang-cl >/dev/null 2>&1 && ! command -v cl >/dev/null 2>&1; then
  echo "cl/clang-cl not found. Run build_msvc.bat (or vcvars64) first."
  exit 1
fi
if ! command -v lib.exe >/dev/null 2>&1 && ! command -v lib >/dev/null 2>&1; then
  echo "lib.exe not found. Run build_msvc.bat (or vcvars64) first."
  exit 1
fi

CC_CMD=clang-cl
command -v clang-cl >/dev/null 2>&1 || CC_CMD=cl
LIB_CMD=lib
command -v lib.exe >/dev/null 2>&1 && LIB_CMD=lib.exe

fix_zconf_for_msvc() {
  # FFmpeg config.h does `#define HAVE_UNISTD_H 0`. zlib's zconf.h uses
  # `#ifdef HAVE_UNISTD_H`, which is still true, so it includes <unistd.h>.
  local zconf="$1"
  [[ -f "$zconf" ]] || return 0
  if grep -q 'defined(Z_HAVE_UNISTD_H) && !defined(_WIN32)' "$zconf"; then
    return 0
  fi
  sed -i 's/#  if defined(Z_HAVE_UNISTD_H)$/#  if defined(Z_HAVE_UNISTD_H) \&\& !defined(_WIN32)/' "$zconf"
}

mkdir -p "$DEPS" "$PREFIX/include" "$PREFIX/lib"

if [[ -f "$PREFIX/lib/zlib.lib" && -f "$PREFIX/include/zlib.h" ]]; then
  echo "==> zlib already built: $PREFIX"
  fix_zconf_for_msvc "$PREFIX/include/zconf.h"
  exit 0
fi

if [[ ! -d "$SRC" ]]; then
  if [[ ! -f "$ARCHIVE" ]]; then
    echo "==> downloading zlib ${ZLIB_VERSION}"
    curl -L --fail -o "$ARCHIVE" "$URL"
  fi
  echo "==> extracting zlib"
  tar -xf "$ARCHIVE" -C "$DEPS"
fi

echo "==> compiling zlib with $CC_CMD"
# MSYS2 rewrites /flag as C:/msys64/flag. clang-cl accepts dash MSVC flags.
export MSYS2_ARG_CONV_EXCL='*'
pushd "$SRC" >/dev/null
rm -f ./*.obj zlib.lib

# Core inflate/deflate only — FFmpeg overrides zalloc/zfree and does not need gz*.
SRCS=(adler32 compress crc32 deflate infback inffast inflate inftrees trees uncompr zutil)
for src in "${SRCS[@]}"; do
  "$CC_CMD" -nologo -c -Z7 -MD -W3 -O2 \
    -D_CRT_SECURE_NO_DEPRECATE -D_CRT_NONSTDC_NO_DEPRECATE \
    -I. "${src}.c"
done

"$LIB_CMD" -nologo -out:zlib.lib \
  adler32.obj compress.obj crc32.obj deflate.obj infback.obj \
  inffast.obj inflate.obj inftrees.obj trees.obj uncompr.obj zutil.obj

cp -f zlib.h zconf.h "$PREFIX/include/"
cp -f zlib.lib "$PREFIX/lib/"
popd >/dev/null
fix_zconf_for_msvc "$PREFIX/include/zconf.h"

echo "==> zlib installed: $PREFIX"
echo "    include: $PREFIX/include"
echo "    lib:     $PREFIX/lib/zlib.lib"
