@echo off
REM ============================================================================
REM  Appliance Manual RAG — Windows launcher
REM  Double-click this file in Explorer to start the app.
REM ============================================================================

setlocal EnableDelayedExpansion
cd /d "%~dp0"

set "BOLD=1"
set "DIM=2"
set "RED=31"
set "GRN=32"
set "YEL=33"
set "CYN=36"
set "RST=0"

REM ── ANSI color support for Windows 10+ ──────────────────────────────────────
for /F "tokens=*" %%i in ('echo prompt $E ^| cmd') do set "ESC=%%i"

call :color %CYN% & echo.===^> %BOLD%Appliance Manual RAG - Windows launcher%RST% & call :color %RST%
echo.

REM ── Read .env (best-effort) ─────────────────────────────────────────────────
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

REM ── 1. Check Ollama ──────────────────────────────────────────────────────────
call :color %CYN% & echo.===^> Checking Ollama...%RST% & call :color %RST%
where ollama >nul 2>&1
if errorlevel 1 (
    call :color %RED% & echo.X Ollama is not installed. & call :color %RST%
    echo Please install it from https://ollama.com/download and run this file again.
    pause
    exit /b 1
)
call :color %GRN% & echo.OK Ollama found & call :color %RST%

curl -fsS -m 3 http://127.0.0.1:11434/api/tags >nul 2>&1
if errorlevel 1 (
    call :color %YEL% & echo.! Ollama server not responding. Start the Ollama app and try again. & call :color %RST%
    pause
    exit /b 1
)
call :color %GRN% & echo.OK Ollama is running & call :color %RST%

REM ── 2. Pull models if missing ───────────────────────────────────────────────
call :pull_model "%OLLAMA_LLM_MODEL%"
call :pull_model "%OLLAMA_EMBED_MODEL%"

REM ── 3. Python venv + requirements ───────────────────────────────────────────
call :color %CYN% & echo.===^> Checking Python...%RST% & call :color %RST%
where python >nul 2>&1
if errorlevel 1 (
    call :color %RED% & echo.X Python not found. Install Python 3.10+ from https://www.python.org/downloads/ & call :color %RST%
    pause
    exit /b 1
)
for /F "tokens=2" %%V in ('python --version 2^>^&1') do set "PYVER=%%V"
call :color %GRN% & echo.OK Python !PYVER! & call :color %RST%

if not exist "venv\Scripts\python.exe" (
    call :color %CYN% & echo.===^> Creating venv...%RST% & call :color %RST%
    python -m venv venv || ( call :color %RED% & echo.X venv creation failed & call :color %RST% & pause & exit /b 1 )
)
call venv\Scripts\activate.bat
python -m pip install --quiet --upgrade pip
call :color %CYN% & echo.===^> Installing Python dependencies [one-time]...%RST% & call :color %RST%
pip install --quiet -r requirements.txt || ( call :color %RED% & echo.X pip install failed & call :color %RST% & pause & exit /b 1 )
call :color %GRN% & echo.OK Python deps ready & call :color %RST%

REM ── 4. Node deps ────────────────────────────────────────────────────────────
call :color %CYN% & echo.===^> Checking Node.js...%RST% & call :color %RST%
where node >nul 2>&1
if errorlevel 1 (
    call :color %RED% & echo.X Node.js not found. Install Node 18+ from https://nodejs.org/ & call :color %RST%
    pause
    exit /b 1
)
for /F "tokens=*" %%V in ('node --version') do set "NODEVER=%%V"
call :color %GRN% & echo.OK Node !NODEVER! & call :color %RST%

if not exist "appliance-rag-ui\node_modules" (
    call :color %CYN% & echo.===^> Installing frontend dependencies [one-time]...%RST% & call :color %RST%
    pushd appliance-rag-ui
    call npm install --no-audit --no-fund --loglevel=error || ( popd & call :color %RED% & echo.X npm install failed & call :color %RST% & pause & exit /b 1 )
    popd
)
call :color %GRN% & echo.OK Frontend deps ready & call :color %RST%

REM ── 5. Start backend in a new window ─────────────────────────────────────────
if not exist logs mkdir logs
call :color %CYN% & echo.===^> Starting backend on port %BACKEND_PORT%...%RST% & call :color %RST%
start "RAG-Backend" /B cmd /c "call venv\Scripts\activate && python -m uvicorn main:app --host 0.0.0.0 --port %BACKEND_PORT% > logs\backend.log 2>&1"

REM ── 6. Start frontend in a new window ────────────────────────────────────────
call :color %CYN% & echo.===^> Starting frontend on port %FRONTEND_PORT%...%RST% & call :color %RST%
pushd appliance-rag-ui
start "RAG-Frontend" /B cmd /c "npm run dev -- --port %FRONTEND_PORT% > ..\logs\frontend.log 2>&1"
popd

REM ── 7. Wait for both to be ready ────────────────────────────────────────────
call :color %CYN% & echo.===^> Waiting for backend...%RST% & call :color %RST%
call :wait_url "http://127.0.0.1:%BACKEND_PORT%/health" 60
call :color %CYN% & echo.===^> Waiting for frontend...%RST% & call :color %RST%
call :wait_url "http://127.0.0.1:%FRONTEND_PORT%" 90

REM ── 8. Open browser ─────────────────────────────────────────────────────────
call :color %GRN% & echo.
echo.OK App is running!
echo.    Backend:  http://127.0.0.1:%BACKEND_PORT%
echo.    Frontend: http://localhost:%FRONTEND_PORT% & call :color %RST%
start "" "http://localhost:%FRONTEND_PORT%"

echo.
echo Close the "RAG-Backend" and "RAG-Frontend" windows to stop the app.
pause
exit /b 0

REM ─────────────────────────────────────────────────────────────────────────────
REM  Helpers
REM ─────────────────────────────────────────────────────────────────────────────
:color
if "%~1"=="" ( <nul set /p "=%ESC%[0m" ) else ( <nul set /p "=%ESC%[%~1m" )
goto :eof

:pull_model
set "MODEL=%~1"
call :color %CYN% & echo.===^> Ensuring model '%MODEL%' is pulled...%RST% & call :color %RST%
curl -fsS -m 3 http://127.0.0.1:11434/api/tags | findstr /C:"\"name\":\"%MODEL%\"" >nul 2>&1
if not errorlevel 1 (
    call :color %GRN% & echo.OK Model '%MODEL%' present & call :color %RST%
    goto :eof
)
echo Downloading %MODEL% - this can take a few minutes on first run...
ollama pull "%MODEL%" || ( call :color %RED% & echo.X Pull failed & call :color %RST% & pause & exit /b 1 )
call :color %GRN% & echo.OK Model '%MODEL%' pulled & call :color %RST%
goto :eof

:wait_url
set "URL=%~1"
set "MAX=%~2"
for /L %%I in (1,1,%MAX%) do (
    curl -fsS -m 2 -o nul "%URL%" >nul 2>&1
    if not errorlevel 1 (
        call :color %GRN% & echo.OK %URL% is up & call :color %RST%
        goto :eof
    )
    timeout /t 1 /nobreak >nul
)
call :color %RED% & echo.X %URL% did not become ready in %MAX%s. Check the log windows. & call :color %RST%
pause
exit /b 1
