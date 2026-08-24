@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem Full MSVC FFmpeg build: vcvars64 (1) + MSYS2 inherit (2) + clang-cl PATH (3) + 1_build_msvc.sh (4)
rem Double-click this file, or run it from any Command Prompt.

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "LLVM_BIN=C:\Program Files\LLVM\bin"
if defined LLVM_HOME set "LLVM_BIN=%LLVM_HOME%\bin"
set "MSYS2=C:\msys64"
if defined MSYS2_HOME set "MSYS2=%MSYS2_HOME%"

if not exist "%VSWHERE%" (
  echo vswhere.exe not found. Install Visual Studio with C++ tools.
  exit /b 1
)

for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%i"
if not defined VSINSTALL (
  echo Visual Studio with MSVC x64 tools was not found.
  exit /b 1
)

echo Using Visual Studio: %VSINSTALL%
call "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
  echo vcvars64.bat failed.
  exit /b 1
)

if exist "%LLVM_BIN%\clang-cl.exe" set "PATH=%LLVM_BIN%;%PATH%"

where cl >nul 2>&1
if errorlevel 1 (
  echo cl.exe not found after vcvars64. Use the x64 Native Tools environment.
  exit /b 1
)
where clang-cl >nul 2>&1
if errorlevel 1 (
  echo clang-cl.exe not found. Install LLVM or set LLVM_HOME.
  echo Expected: %LLVM_BIN%\clang-cl.exe
  exit /b 1
)

if not exist "%MSYS2%\usr\bin\bash.exe" (
  echo MSYS2 bash not found at %MSYS2%
  echo Install MSYS2 or set MSYS2_HOME.
  exit /b 1
)

rem inherit = keep cl/clang-cl from vcvars. Do not use bash -l: a login shell
rem rewrites the huge VS PATH and can sit there for minutes with no output.
set "MSYS2_PATH_TYPE=inherit"
set "MSYSTEM=MSYS"
set "PATH=%MSYS2%\usr\bin;%PATH%"

rem Do not call cygpath from for /f: cmd quote-parsing breaks on paths with spaces
rem (D:\Source Code\...) and leaves MSYS_PWD empty. Map D:\foo -> /D/foo in-bat.
set "MSYS_PWD=/%CD:~0,1%%CD:~2%"
set "MSYS_PWD=%MSYS_PWD:\=/%"

echo.
echo Building FFmpeg MSVC shared libraries
echo   source: %CD%
echo   msys:   %MSYS_PWD%
echo Launching 1_build_msvc.sh
echo   configure prints a long summary after a few minutes, then make runs.
echo.

"%MSYS2%\usr\bin\bash.exe" -c "cd '%MSYS_PWD%' && ./1_build_msvc.sh"
echo.
echo FFmpeg build finished with exit code %ERRORLEVEL%
exit /b %ERRORLEVEL%
