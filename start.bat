@echo off
REM ============================================================================
REM  Appliance Manual RAG — Windows Launcher
REM
REM  Uses the local runtimes installed by install.bat.
REM  Double-click this file in Explorer to start the app.
REM ============================================================================

setlocal EnableDelayedExpansion
cd /d "%~dp0"
title Appliance Manual RAG

REM ── Paths to local runtimes ───────────────────────────────────────────────────
set "RUNTIME=%~dp0_runtime"
set "PY_DIR=%RUNTIME%\python"
set "NODE_DIR=%RUNTIME%\node"

REM ── Read .env (best-effort) ──────────────────────────────────────────────────
set "OLLAMA_LLM_MODEL=hermes3"
set "OLLAMA_EMBED_MODEL=nomic-embed-text"
set "BACKEND_PORT=8000"
set "FRONTEND_PORT=3000"
if exist ".env" (
    for /F "usebackq tokens=1,2 delims==" %%A in (".env") do (
        if /I "%%A"=="OLLAMA_LLM_MODEL"   set "OLLAMA_LLM_MODEL=%%B"
        if /I "%%A"=="OLLAMA_EMBED_MODEL"  set "OLLAMA_EMBED_MODEL=%%B"
        if /I "%%A"=="BACKEND_PORT"        set "BACKEND_PORT=%%B"
        if /I "%%A"=="FRONTEND_PORT"       set "FRONTEND_PORT=%%B"
    )
)

REM ── Banner ────────────────────────────────────────────────────────────────────
echo.
echo  ============================================================
echo         Appliance Manual RAG — Starting...
echo  ============================================================
echo.

REM ── Resolve Python ────────────────────────────────────────────────────────────
REM  Priority: local embedded Python ^> system venv ^> system Python
set "PYTHON_EXE="
if exist "%PY_DIR%\python.exe" (
    set "PYTHON_EXE=%PY_DIR%\python.exe"
    set "PY_SOURCE=local runtime"
) else if exist "venv\Scripts\python.exe" (
    call venv\Scripts\activate.bat
    set "PYTHON_EXE=python"
    set "PY_SOURCE=venv"
) else (
    where python >nul 2>&1
    if not errorlevel 1 (
        set "PYTHON_EXE=python"
        set "PY_SOURCE=system PATH"
    )
)
if not defined PYTHON_EXE (
    echo  [X] Python not found.
    echo.
    echo  Run install.bat first to set up all dependencies.
    echo.
    pause
    exit /b 1
)
echo  [OK] Python (%PY_SOURCE%)

REM ── Resolve Node.js ───────────────────────────────────────────────────────────
REM  Priority: local portable Node ^> system Node
set "NODE_EXE="
set "NPM_CMD="
if exist "%NODE_DIR%\node.exe" (
    set "NODE_EXE=%NODE_DIR%\node.exe"
    set "NPM_CMD=%NODE_DIR%\npm.cmd"
    set "PATH=%NODE_DIR%;%PATH%"
    set "NODE_SOURCE=local runtime"
) else (
    where node >nul 2>&1
    if not errorlevel 1 (
        set "NODE_EXE=node"
        set "NPM_CMD=npm.cmd"
        set "NODE_SOURCE=system PATH"
    )
)
if not defined NODE_EXE (
    echo  [X] Node.js not found.
    echo.
    echo  Run install.bat first to set up all dependencies.
    echo.
    pause
    exit /b 1
)
echo  [OK] Node.js (%NODE_SOURCE%)

REM ── Resolve Ollama ────────────────────────────────────────────────────────────
set "OLLAMA_EXE="
where ollama >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('where ollama 2^>nul') do (
        if not defined OLLAMA_EXE set "OLLAMA_EXE=%%i"
    )
)
if not defined OLLAMA_EXE (
    if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" (
        set "OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"
    )
)
if not defined OLLAMA_EXE (
    echo  [X] Ollama not found.
    echo.
    echo  Run install.bat first, or install Ollama from https://ollama.com/download
    echo.
    pause
    exit /b 1
)
echo  [OK] Ollama found

REM ── Ensure frontend deps are installed ────────────────────────────────────────
if not exist "appliance-rag-ui\node_modules" (
    echo.
    echo  [i] Frontend packages not installed. Running npm install...
    pushd appliance-rag-ui
    call "%NPM_CMD%" install --no-audit --no-fund --loglevel=error
    if !errorlevel! neq 0 (
        popd
        echo  [X] npm install failed.
        pause
        exit /b 1
    )
    popd
    echo  [OK] Frontend packages installed.
)

REM ── Ensure Python deps are installed ──────────────────────────────────────────
REM  Quick check: see if uvicorn is importable
"%PYTHON_EXE%" -c "import uvicorn" 2>nul
if errorlevel 1 (
    echo.
    echo  [i] Python packages not installed. Running pip install...
    "%PYTHON_EXE%" -m pip install --quiet --no-warn-script-location -r requirements.txt
    if !errorlevel! neq 0 (
        echo  [X] pip install failed.
        pause
        exit /b 1
    )
    echo  [OK] Python packages installed.
)

REM ── Start Ollama if not running ───────────────────────────────────────────────
echo.
echo  [..] Checking Ollama server...
curl.exe -fsS -m 3 http://127.0.0.1:11434/api/tags >nul 2>&1
if not errorlevel 1 goto :ollama_up

echo  [i] Ollama not running. Starting it now...
start "Ollama-Serve" /MIN cmd /c ""%OLLAMA_EXE%" serve"

set "WAIT=0"
:wait_ollama
if !WAIT! geq 30 (
    echo  [X] Ollama did not start within 30 seconds.
    echo      Make sure nothing else is using port 11434.
    pause
    exit /b 1
)
curl.exe -fsS -m 2 http://127.0.0.1:11434/api/tags >nul 2>&1
if not errorlevel 1 goto :ollama_up
set /a WAIT+=1
timeout /t 1 /nobreak >nul
goto :wait_ollama

:ollama_up
echo  [OK] Ollama is running

REM ── Pull models if missing ────────────────────────────────────────────────────
echo.
echo  [..] Checking AI models...
call :check_and_pull "%OLLAMA_LLM_MODEL%"
call :check_and_pull "%OLLAMA_EMBED_MODEL%"

REM ── Create log directory ──────────────────────────────────────────────────────
if not exist logs mkdir logs

REM ── Start backend ─────────────────────────────────────────────────────────────
echo.
echo  [..] Starting backend on port %BACKEND_PORT%...
start "RAG-Backend" /B cmd /c ""%PYTHON_EXE%" -m uvicorn main:app --host 0.0.0.0 --port %BACKEND_PORT% > logs\backend.log 2>&1"

REM ── Start frontend ────────────────────────────────────────────────────────────
echo  [..] Starting frontend on port %FRONTEND_PORT%...
pushd appliance-rag-ui
start "RAG-Frontend" /B cmd /c ""%NPM_CMD%" run dev -- --port %FRONTEND_PORT% > ..\logs\frontend.log 2>&1"
popd

REM ── Wait for both servers ─────────────────────────────────────────────────────
echo.
echo  [..] Waiting for backend to start...
call :wait_url "http://127.0.0.1:%BACKEND_PORT%/health" 60
if !errorlevel! neq 0 (
    echo  [X] Backend did not start. Check logs\backend.log for errors.
    pause
    exit /b 1
)

echo  [..] Waiting for frontend to start...
call :wait_url "http://127.0.0.1:%FRONTEND_PORT%" 90
if !errorlevel! neq 0 (
    echo  [X] Frontend did not start. Check logs\frontend.log for errors.
    pause
    exit /b 1
)

REM ── Open browser ──────────────────────────────────────────────────────────────
echo.
echo  ============================================================
echo.
echo   App is running!
echo.
echo     Backend:  http://127.0.0.1:%BACKEND_PORT%
echo     Frontend: http://localhost:%FRONTEND_PORT%
echo.
echo   Press any key in this window to STOP the app.
echo.
echo  ============================================================
start "" "http://localhost:%FRONTEND_PORT%"

pause >nul

REM ── Cleanup: kill background processes ────────────────────────────────────────
echo.
echo  Stopping servers...
taskkill /FI "WINDOWTITLE eq RAG-Backend*" /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq RAG-Frontend*" /F >nul 2>&1

REM Also kill by process if the above didn't catch them
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr ":%BACKEND_PORT% " ^| findstr "LISTENING"') do (
    taskkill /PID %%p /F >nul 2>&1
)
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr ":%FRONTEND_PORT% " ^| findstr "LISTENING"') do (
    taskkill /PID %%p /F >nul 2>&1
)

echo  Stopped. You can close this window.
timeout /t 3 >nul
exit /b 0

REM ═══════════════════════════════════════════════════════════════════════════════
REM  Helpers
REM ═══════════════════════════════════════════════════════════════════════════════

:check_and_pull
REM Usage: call :check_and_pull "model-name"
set "MODEL=%~1"
REM Try to detect if the model is already present via Ollama API
curl.exe -fsS http://127.0.0.1:11434/api/tags 2>nul | findstr /I "%MODEL%" >nul 2>&1
if not errorlevel 1 (
    echo  [OK] Model '%MODEL%' is available
    goto :eof
)
echo  [i] Pulling '%MODEL%' (this may take several minutes on first run)...
"%OLLAMA_EXE%" pull "%MODEL%"
if errorlevel 1 (
    echo  [!] Failed to pull '%MODEL%'. The app may not work correctly.
    echo      Try manually: ollama pull %MODEL%
) else (
    echo  [OK] Model '%MODEL%' pulled successfully
)
goto :eof

:wait_url
REM Usage: call :wait_url "http://..." timeout_seconds
REM Returns errorlevel 0 on success, 1 on timeout
set "URL=%~1"
set "MAX=%~2"
set "W=0"
:wait_url_loop
if !W! geq %MAX% (
    exit /b 1
)
curl.exe -sS -m 2 -o nul "%URL%" >nul 2>&1
if not errorlevel 1 (
    echo  [OK] %URL% is up
    exit /b 0
)
set /a W+=1
timeout /t 1 /nobreak >nul
goto :wait_url_loop
