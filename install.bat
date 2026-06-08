@echo off
REM ============================================================================
REM  Appliance Manual RAG — One-Time Installer for Windows
REM
REM  Downloads and sets up ALL dependencies locally:
REM    - Python 3.12 (embedded, portable — no system install)
REM    - Node.js 20 LTS (portable — no system install)
REM    - Ollama (AI model runtime — silent install)
REM    - Backend Python packages (fastapi, llama-index, etc.)
REM    - Frontend npm packages (Next.js, React)
REM    - AI models (hermes3 + nomic-embed-text)
REM
REM  After this finishes, double-click start.bat to launch the app.
REM ============================================================================

setlocal EnableDelayedExpansion
cd /d "%~dp0"
title Appliance Manual RAG — Installer

REM ── Version Configuration ─────────────────────────────────────────────────────
REM  Update these to change which versions get installed.
set "PY_VERSION=3.12.8"
set "PY_TAG=312"
set "NODE_VERSION=20.18.1"

set "PY_URL=https://www.python.org/ftp/python/%PY_VERSION%/python-%PY_VERSION%-embed-amd64.zip"
set "PIP_URL=https://bootstrap.pypa.io/get-pip.py"
set "NODE_URL=https://nodejs.org/dist/v%NODE_VERSION%/node-v%NODE_VERSION%-win-x64.zip"
set "OLLAMA_URL=https://ollama.com/download/OllamaSetup.exe"

REM ── Paths ─────────────────────────────────────────────────────────────────────
set "RUNTIME=%~dp0_runtime"
set "PY_DIR=%RUNTIME%\python"
set "NODE_DIR=%RUNTIME%\node"

REM ── Read .env for model names (use defaults if no .env) ───────────────────────
set "OLLAMA_LLM_MODEL=hermes3"
set "OLLAMA_EMBED_MODEL=nomic-embed-text"
if exist ".env" (
    for /F "usebackq tokens=1,2 delims==" %%A in (".env") do (
        if /I "%%A"=="OLLAMA_LLM_MODEL"  set "OLLAMA_LLM_MODEL=%%B"
        if /I "%%A"=="OLLAMA_EMBED_MODEL" set "OLLAMA_EMBED_MODEL=%%B"
    )
)

REM ── Banner ────────────────────────────────────────────────────────────────────
echo.
echo  ============================================================
echo         Appliance Manual RAG — One-Time Installer
echo  ============================================================
echo.
echo   This will download and set up all required components:
echo.
echo     [1] Python %PY_VERSION%  (local, portable)
echo     [2] pip             (Python package manager)
echo     [3] Backend packages (FastAPI, LlamaIndex, etc.)
echo     [4] Node.js %NODE_VERSION%  (local, portable)
echo     [5] Frontend packages (Next.js, React)
echo     [6] Ollama          (AI model runtime)
echo     [7] AI models       (%OLLAMA_LLM_MODEL% + %OLLAMA_EMBED_MODEL%)
echo.
echo   Total download: ~500 MB on first run.
echo   Estimated time: 5-15 minutes (depends on internet speed).
echo  ============================================================
echo.
echo  Press any key to start, or close this window to cancel.
pause >nul

REM ── Verify curl is available (ships with Windows 10 1803+) ────────────────────
where curl.exe >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: curl.exe not found.
    echo  This installer requires Windows 10 version 1803 or later.
    echo.
    pause
    exit /b 1
)

REM ── Create directories ────────────────────────────────────────────────────────
if not exist "%RUNTIME%" mkdir "%RUNTIME%"
if not exist "documents" mkdir "documents"
if not exist "storage" mkdir "storage"
if not exist "logs" mkdir "logs"

REM ── Create .env from example if missing ───────────────────────────────────────
if not exist ".env" (
    if exist ".env.example" (
        copy ".env.example" ".env" >nul
        echo  [i] Created .env from .env.example
    )
)
if not exist "appliance-rag-ui\.env.local" (
    if exist "appliance-rag-ui\.env.example" (
        copy "appliance-rag-ui\.env.example" "appliance-rag-ui\.env.local" >nul
        echo  [i] Created frontend .env.local from .env.example
    )
)

echo.

REM ════════════════════════════════════════════════════════════════════════════════
REM  STEP 1 — Python (embedded / portable)
REM ════════════════════════════════════════════════════════════════════════════════
echo  [1/7] Python %PY_VERSION% ...
if exist "%PY_DIR%\python.exe" (
    echo         Already installed. Skipping download.
) else (
    echo         Downloading python-%PY_VERSION%-embed-amd64.zip ...
    curl.exe -L --progress-bar -o "%RUNTIME%\python.zip" "%PY_URL%"
    if !errorlevel! neq 0 (
        echo.
        echo  FAILED: Could not download Python.
        echo  Check your internet connection and try again.
        pause
        exit /b 1
    )
    echo         Extracting ...
    if not exist "%PY_DIR%" mkdir "%PY_DIR%"
    tar.exe -xf "%RUNTIME%\python.zip" -C "%PY_DIR%"
    if !errorlevel! neq 0 (
        echo  FAILED: Could not extract Python archive.
        pause
        exit /b 1
    )
    del /q "%RUNTIME%\python.zip" 2>nul

    REM Enable "import site" in the ._pth file so pip/packages work
    powershell -NoProfile -Command ^
        "$f = '%PY_DIR%\python%PY_TAG%._pth'; " ^
        "(Get-Content $f) -replace '^\s*#\s*import site','import site' | Set-Content $f"
    echo         [OK] Python %PY_VERSION% extracted.
)
echo.

REM ════════════════════════════════════════════════════════════════════════════════
REM  STEP 2 — pip
REM ════════════════════════════════════════════════════════════════════════════════
echo  [2/7] pip ...
if exist "%PY_DIR%\Scripts\pip.exe" (
    echo         Already installed. Skipping.
) else (
    echo         Downloading get-pip.py ...
    curl.exe -L --progress-bar -o "%RUNTIME%\get-pip.py" "%PIP_URL%"
    if !errorlevel! neq 0 (
        echo  FAILED: Could not download get-pip.py.
        pause
        exit /b 1
    )
    echo         Installing pip (this takes a moment) ...
    "%PY_DIR%\python.exe" "%RUNTIME%\get-pip.py" --no-warn-script-location 2>nul
    if !errorlevel! neq 0 (
        echo  FAILED: pip installation failed.
        pause
        exit /b 1
    )
    del /q "%RUNTIME%\get-pip.py" 2>nul
    echo         [OK] pip installed.
)
echo.

REM ════════════════════════════════════════════════════════════════════════════════
REM  STEP 3 — Python backend packages
REM ════════════════════════════════════════════════════════════════════════════════
echo  [3/7] Python packages ...
echo         Installing from requirements.txt ...
echo         (fastapi, uvicorn, llama-index, pandas, ...)
"%PY_DIR%\python.exe" -m pip install --quiet --no-warn-script-location -r requirements.txt
if !errorlevel! neq 0 (
    echo.
    echo  FAILED: Python package installation failed.
    echo  Check the output above for errors.
    pause
    exit /b 1
)
echo         [OK] All backend packages installed.
echo.

REM ════════════════════════════════════════════════════════════════════════════════
REM  STEP 4 — Node.js (portable)
REM ════════════════════════════════════════════════════════════════════════════════
echo  [4/7] Node.js %NODE_VERSION% ...
if exist "%NODE_DIR%\node.exe" (
    echo         Already installed. Skipping download.
) else (
    echo         Downloading node-v%NODE_VERSION%-win-x64.zip ...
    curl.exe -L --progress-bar -o "%RUNTIME%\node.zip" "%NODE_URL%"
    if !errorlevel! neq 0 (
        echo  FAILED: Could not download Node.js.
        pause
        exit /b 1
    )
    echo         Extracting ...
    tar.exe -xf "%RUNTIME%\node.zip" -C "%RUNTIME%"
    if !errorlevel! neq 0 (
        echo  FAILED: Could not extract Node.js archive.
        pause
        exit /b 1
    )
    if exist "%RUNTIME%\node-v%NODE_VERSION%-win-x64" (
        move /Y "%RUNTIME%\node-v%NODE_VERSION%-win-x64" "%NODE_DIR%" >nul
    )
    if !errorlevel! neq 0 (
        echo  FAILED: Could not extract Node.js archive.
        pause
        exit /b 1
    )
    del /q "%RUNTIME%\node.zip" 2>nul
    echo         [OK] Node.js %NODE_VERSION% extracted.
)
echo.

REM ════════════════════════════════════════════════════════════════════════════════
REM  STEP 5 — Frontend npm packages
REM ════════════════════════════════════════════════════════════════════════════════
echo  [5/7] Frontend packages ...
set "PATH=%NODE_DIR%;%PATH%"
pushd appliance-rag-ui
echo         Running npm install ...
call "%NODE_DIR%\npm.cmd" install --no-audit --no-fund --loglevel=error
if !errorlevel! neq 0 (
    popd
    echo  FAILED: npm install failed.
    pause
    exit /b 1
)
popd
echo         [OK] Frontend packages installed.
echo.

REM ════════════════════════════════════════════════════════════════════════════════
REM  STEP 6 — Ollama
REM ════════════════════════════════════════════════════════════════════════════════
echo  [6/7] Ollama ...
set "OLLAMA_EXE="

REM Check if ollama is already on PATH
where ollama >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('where ollama 2^>nul') do (
        if not defined OLLAMA_EXE set "OLLAMA_EXE=%%i"
    )
    echo         Already installed on PATH.
    goto :ollama_installed
)

REM Check standard Windows install location
if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" (
    set "OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"
    echo         Found at standard location.
    goto :ollama_installed
)

REM Not found — download and install
echo         Ollama not found. Downloading installer (~300 MB) ...
curl.exe -L --progress-bar -o "%RUNTIME%\OllamaSetup.exe" "%OLLAMA_URL%"
if !errorlevel! neq 0 (
    echo  FAILED: Could not download Ollama installer.
    echo  You can install it manually from https://ollama.com/download
    pause
    exit /b 1
)
echo         Installing Ollama ...
echo         (You may see a Windows security prompt — click Yes)
start /wait "" "%RUNTIME%\OllamaSetup.exe" /VERYSILENT
del /q "%RUNTIME%\OllamaSetup.exe" 2>nul

REM Verify installation
if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" (
    set "OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"
    echo         [OK] Ollama installed successfully.
) else (
    echo.
    echo  WARNING: Ollama installation may have failed.
    echo  Please install it manually from: https://ollama.com/download
    echo  Then run this installer again.
    echo.
    pause
    exit /b 1
)

:ollama_installed
echo.

REM ════════════════════════════════════════════════════════════════════════════════
REM  STEP 7 — Pull AI models
REM ════════════════════════════════════════════════════════════════════════════════
echo  [7/7] AI models ...

REM Start Ollama serve if the API is not responding
curl.exe -fsS -m 3 http://127.0.0.1:11434/api/tags >nul 2>&1
if not errorlevel 1 goto :ollama_ready

echo         Starting Ollama server ...
start "Ollama-Serve" /MIN cmd /c ""%OLLAMA_EXE%" serve"

REM Wait up to 30 seconds for Ollama to become ready
set "WAIT=0"
:wait_ollama
if !WAIT! geq 30 (
    echo         WARNING: Ollama did not start within 30 seconds.
    echo         Models will be pulled automatically when you run start.bat.
    goto :install_done
)
curl.exe -fsS -m 2 http://127.0.0.1:11434/api/tags >nul 2>&1
if not errorlevel 1 goto :ollama_ready
set /a WAIT+=1
timeout /t 1 /nobreak >nul
goto :wait_ollama

:ollama_ready
echo         Ollama server is running.

echo         Pulling %OLLAMA_LLM_MODEL% (this may take several minutes on first run) ...
"%OLLAMA_EXE%" pull "%OLLAMA_LLM_MODEL%"
if !errorlevel! neq 0 (
    echo  WARNING: Failed to pull %OLLAMA_LLM_MODEL%.
    echo  You can pull it manually later: ollama pull %OLLAMA_LLM_MODEL%
)

echo         Pulling %OLLAMA_EMBED_MODEL% ...
"%OLLAMA_EXE%" pull "%OLLAMA_EMBED_MODEL%"
if !errorlevel! neq 0 (
    echo  WARNING: Failed to pull %OLLAMA_EMBED_MODEL%.
    echo  You can pull it manually later: ollama pull %OLLAMA_EMBED_MODEL%
)

echo         [OK] Models ready.

:install_done
echo.
echo  ============================================================
echo.
echo   Installation complete!
echo.
echo   To start the application:
echo     1. Double-click  start.bat
echo     2. Wait for the browser to open
echo     3. Upload a document and start asking questions!
echo.
echo   To stop: close the console window, or press any key in it.
echo.
echo  ============================================================
echo.
pause
exit /b 0
