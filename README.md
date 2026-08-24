# Building FFmpeg with clang-cl on Windows

Building FFmpeg with clang-cl on Windows requires MSYS2 + Visual Studio.

---

## Prerequisites

- **Visual Studio 2019/2022** with "Desktop development with C++" workload
- **MSYS2** — https://www.msys2.org
- **NASM** — install via MSYS2 pacman (see Step 1)
- **clang-cl** — install via Visual Studio Installer (see below)

### Install clang-cl via Visual Studio Installer

```
Visual Studio Installer
- Modify
- Individual Components
- search "Clang"
- "C++ Clang Compiler for Windows"
- "MSBuild support for LLVM"
- Modify (install)
```

Installed to:
```
C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\Llvm\x64\bin\clang-cl.exe
```

> **Note:** clang-cl must come from Visual Studio — not from MSYS2 pacman.
> The MSYS2 clang does not know about MSVC headers/libs and cannot produce MSVC-format PDB files.

---

## Step 1 — Install MSYS2 Packages

Open **MSYS2 MinGW64** shell:

```bash
pacman -S make diffutils pkg-config nasm
```

---

## Step 2 — Launch the Right Shell

You must start MSYS2 **from an x64 Native Tools Command Prompt** so that MSVC
environment variables (`LIB`, `INCLUDE`, `PATH`) are inherited correctly.

```
Start Menu → search:
"x64 Native Tools Command Prompt for VS 2022"
```

> **Important:** Do NOT use the plain "Developer Command Prompt" — it defaults to x86.

Then from that prompt launch MSYS2:

```cmd
set MSYS2_PATH_TYPE=inherit
C:\msys64\msys2_shell.cmd -mingw64 -use-full-path
```

### Automated MSVC build

From any Command Prompt or Explorer, in this repo:

```cmd
build_msvc.bat
```

That runs vcvars64 (x64 MSVC), inherits that environment into MSYS2, puts LLVM `clang-cl` on PATH, then `./1_build_msvc.sh`.

`1_build_msvc.sh` first builds a static MSVC `zlib.lib` (`0_build_zlib_msvc.sh`) and passes `--enable-zlib`. zlib is added through the MSVC `INCLUDE`/`LIB` environment variables, not `--extra-cflags`, because this tree lives under `Source Code` and a space in `-I`/`-L` splits the compiler command. Without zlib, FFmpeg disables the **png** decoder (and apng, exr, and other inflate-based codecs), so PNG image sequences fail while JPEG sequences still work.

If you are already in an MSYS2 shell started from the x64 Native Tools prompt:

```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
./1_build_msvc.sh
```

DLLs land in `build/install/bin/`.

### Verify the tools are visible inside MSYS2

```bash
cl 2>&1 | head -1      # must say "for x64"
clang-cl --version     # must say Target: x86_64-pc-windows-msvc
which nasm             # must find nasm
```

If any of these say x86 or are not found — do not proceed with configure.

---

## Step 3 — Configure FFmpeg

Navigate to your FFmpeg source inside the MSYS2 shell:

```bash
cd /c/path/to/ffmpeg-source
```

Run configure:

```bash
./configure \
  --toolchain=msvc \
  --arch=x86_64 \
  --target-os=win64 \
  --cc=clang-cl \
  --cxx=clang-cl \
  --enable-debug=3 \
  --disable-optimizations \
  --disable-stripping \
  --enable-shared \
  --disable-static \
  --prefix=./build
```

### Key flags explained

| Flag | Why |
|---|---|
| `--toolchain=msvc` | Tells FFmpeg to use MSVC-style compiler flags |
| `--arch=x86_64` | Explicitly target 64-bit |
| `--cc=clang-cl` | Use clang-cl instead of cl.exe |
| `--enable-debug=3` | Maximum debug info, forces `-Zi` flag |
| `--disable-optimizations` | Disables `/O2`, keeps stack frames intact for debugging |
| `--disable-stripping` | Don't strip symbols from output |
| `--enable-shared` | Build `.dll` + `.lib` + `.pdb` |
| `--enable-zlib` | Required for **png** (and apng/exr). Use `1_build_msvc.sh` so zlib is built first. |

Prefer `build_msvc.bat` over copying this block: the bat file builds zlib and fails configure if PNG is still off.

### Confirm configure detected x64

```bash
cat ffbuild/config.mak | grep ARCH
# Should show: ARCH=x86_64
```

---

## Step 4 — Build

```bash
make -j$(nproc)
make install
```

### Output in `./build/`

```
build/
  bin/
    avcodec-62.dll
    avformat-62.dll
    avutil-59.dll
    ...
  lib/
    avcodec.lib
    avformat.lib
    avutil.lib
    ...
  include/
    libavcodec/
    libavformat/
    libavutil/
    ...
```

---

## Step 5 — Collect PDB Files

FFmpeg's `make install` does not copy `.pdb` files to `build/bin/` automatically.
They are written next to the object files in the build tree. Copy them manually:

```bash
find . -name "*.pdb" -exec cp {} ./build/bin/ \;
```

### Verify PDB is linked into the DLL

```cmd
dumpbin /PDBPATH avcodec-62.dll
# Should show: PDB file: avcodec-62.pdb
```

---

## Step 6 — Load Symbols in MSVC

Place the `.pdb` files next to the `.dll` files in your project output directory.
MSVC will auto-load them if they are in the same folder.

Or add the path explicitly:

```
Debug → Options → Debugging → Symbols
→ click "+" → add path to build/bin
```

Your call stack will now show full function names and source lines:

```
avcodec-62.dll!avcodec_open2()       libavcodec/avcodec.c:500
avcodec-62.dll!ff_codec_open2()      libavcodec/avcodec.c:350
avcodec-62.dll!my_codec_init()       libavcodec/my_codec.c:25
my_encoder.dll!myencoder_init()      myencoder.cpp:15
```

---

## Common Errors

### `nasm not found`
```bash
pacman -S nasm
```

### `cl.exe not found`
You did not launch MSYS2 from the x64 Native Tools Command Prompt. Re-launch using Step 2.

### FFmpeg built as 32-bit
Verify with:
```cmd
dumpbin /HEADERS avutil-59.dll | findstr machine
# Must show: 8664 machine (x64)
# If it shows: 14C machine (x86) → wrong shell, see Step 2
```

### No `.pdb` files generated
Check that debug flags took effect:
```bash
cat ffbuild/config.mak | grep -E "CFLAGS|DEBUG"
# Should contain -Zi and -Od
```
If not, re-run configure and rebuild with `make clean` first.

### clang-cl not found inside MSYS2
Pass the full path explicitly to configure:
```bash
./configure \
  --cc="C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/Llvm/x64/bin/clang-cl.exe" \
  --cxx="C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/Llvm/x64/bin/clang-cl.exe" \
  ...
```

## PNG image sequences and matching a gyan.dev full build

FFmpeg does not have a separate "image sequence codec". `image2` is a **demuxer** (always enabled). Each frame is decoded by the still-image decoder for that extension:

| Extension | Decoder | Extra dependency |
|---|---|---|
| `.jpg` / `.jpeg` | `mjpeg` | none (native) |
| `.png` | `png` | **zlib** |
| `.tif` / `.tiff` | `tiff` | zlib optional (compressed TIFF) |
| `.exr` | `exr` | **zlib** |
| `.bmp` `.tga` `.dpx` | native | none |

`--enable-decoder=png` is not enough. `png_decoder_select="inflate_wrapper"` and `inflate_wrapper_deps="zlib"`. If configure cannot find `zlib.h` + `zlib.lib`, `CONFIG_PNG_DECODER` stays 0 and Prism's `avcodec_find_decoder(AV_CODEC_ID_PNG)` fails.

MSVC has no system zlib (MinGW `pacman` zlib is the wrong ABI). The MSVC path builds zlib with clang-cl and links it statically into the FFmpeg DLLs — no `zlib1.dll` to ship.

After a rebuild, confirm:

```cmd
ffmpeg.exe -hide_banner -decoders | findstr png
ffmpeg.exe -i D:\path\frame_%04d.png -f null -
```

You should see `VFS..D png` (and `apng`). Then copy the install into Prism:

```cmd
Dependencies\FFmpeg\sync_to_prism.bat "D:\Source Code\AvolitesLtd\FFmpeg\build\install"
```

### Same decoder list as a gyan.dev `full_build` README

A default FFmpeg configure already enables **all native** decoders whose dependencies are present. You do **not** copy gyan's decoder list into `--enable-decoder=...`.

What that README is listing:

1. **Native codecs** (h264, hevc, mjpeg, png, bmp, tiff, …) — enabled here once zlib is found. This is what PNG sequences need.
2. **External-lib codecs** (`libdav1d`, `libjxl`, `libaom_av1`, `libvpx_*`, `libopus`, …) — each needs that library **built for MSVC** (`--enable-libdav1d`, `--enable-libjxl`, …). Gyan's MinGW full build ships dozens of those; this MSVC tree does not.
3. **Native fallbacks** still exist without those libs: FFmpeg's own `av1`, `vp8`, `vp9`, `opus`, `webp`, `jpeg2000` decoders.

Matching gyan's *entire* external-library decoder list is a separate MSVC port of those libraries, not a configure switch. For Prism image sequences, zlib + native png is the required piece.

Native Windows compilation using MSYS2
=============

1. Install MSYS2 http://msys2.github.io/.
2. Launch MinGW-w64 and navigate the folder where "Configure" is located.
3. Run "./0_install_deps.sh": install all the necessary dependencies.
4. Run "./1_build.sh": make and install the dlls.
5. -> DLLs can be found at \build\install.

GCC doesn't produce .pdb files natively.

FFmpeg README
=============

FFmpeg is a collection of libraries and tools to process multimedia content
such as audio, video, subtitles and related metadata.

## Libraries

* `libavcodec` provides implementation of a wider range of codecs.
* `libavformat` implements streaming protocols, container formats and basic I/O access.
* `libavutil` includes hashers, decompressors and miscellaneous utility functions.
* `libavfilter` provides means to alter decoded audio and video through a directed graph of connected filters.
* `libavdevice` provides an abstraction to access capture and playback devices.
* `libswresample` implements audio mixing and resampling routines.
* `libswscale` implements color conversion and scaling routines.

## Tools

* [ffmpeg](https://ffmpeg.org/ffmpeg.html) is a command line toolbox to
  manipulate, convert and stream multimedia content.
* [ffplay](https://ffmpeg.org/ffplay.html) is a minimalistic multimedia player.
* [ffprobe](https://ffmpeg.org/ffprobe.html) is a simple analysis tool to inspect
  multimedia content.
* Additional small tools such as `aviocat`, `ismindex` and `qt-faststart`.

## Documentation

The offline documentation is available in the **doc/** directory.

The online documentation is available in the main [website](https://ffmpeg.org)
and in the [wiki](https://trac.ffmpeg.org).

### Examples

Coding examples are available in the **doc/examples** directory.

## License

FFmpeg codebase is mainly LGPL-licensed with optional components licensed under
GPL. Please refer to the LICENSE file for detailed information.

## Contributing

Patches should be submitted to the ffmpeg-devel mailing list using
`git format-patch` or `git send-email`. Github pull requests should be
avoided because they are not part of our review process and will be ignored.
