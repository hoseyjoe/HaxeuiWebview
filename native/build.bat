@echo off
:: Builds webview.hdll (HashLink native extension) into build\heaps.
:: Needs MSVC (found via vswhere), HashLink (hl.exe on PATH, or HASHLINK set)
:: and the HxWebView haxelib for webview.h / WebView2.h.
setlocal
cd /d "%~dp0"

set OUT_DIR=..\build\heaps

if "%HASHLINK%"=="" for %%i in (hl.exe) do set HASHLINK=%%~dp$PATH:i
if "%HASHLINK%"=="" (
    echo HashLink not found: put hl.exe on PATH or set HASHLINK
    exit /b 1
)
if not "%HASHLINK:~-1%"=="\" set HASHLINK=%HASHLINK%\

for /f "delims=" %%i in ('haxelib libpath HxWebView') do set HXWEBVIEW=%%i
if not exist "%HXWEBVIEW%internal\vendor\webview.h" (
    echo HxWebView haxelib not found
    exit /b 1
)

for /f "delims=" %%i in ('"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -property installationPath') do set VS_ROOT=%%i
call "%VS_ROOT%\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1 || (
    echo MSVC x64 toolchain not found
    exit /b 1
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
if not exist obj mkdir obj

cl.exe /nologo /std:c++17 /EHsc /LD /MD /O2 /W3 ^
    /I "%HASHLINK%include" ^
    /I "%HXWEBVIEW%internal\vendor" ^
    /I "%HXWEBVIEW%internal\windows" ^
    /Fo"obj\\" ^
    webview_hl.cpp ^
    /link /LIBPATH:"%HASHLINK%" libhl.lib ^
    /OUT:"%OUT_DIR%\webview.hdll" /IMPLIB:"obj\webview.lib" /PDB:"%OUT_DIR%\webview.pdb"

if errorlevel 1 (
    echo BUILD FAILED
    exit /b 1
)
echo Built %OUT_DIR%\webview.hdll
