#!/usr/bin/env bash
# Shared helpers for the local launchers (start.bat / start.command / start.sh)
# Sourced, not executed. All functions are POSIX-ish bash — Windows start.bat
# is generated separately and doesn't source this file.

set -u

# ─── Paths ────────────────────────────────────────────────────────────────────
# PROJECT_ROOT is the parent of the scripts/ directory.
SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPTS_DIR/.." && pwd )"
cd "$PROJECT_ROOT"

# ─── UI defaults (read from .env or .env.example if present) ──────────────────
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"

# Pull the LLM/embed model names from .env so the launcher can `ollama pull` them.
read_env_var() {
    local key="$1" default="$2"
    local file="$PROJECT_ROOT/.env"
    [[ -f "$file" ]] || { echo "$default"; return; }
    local v
    v=$(grep -E "^${key}=" "$file" | head -1 | cut -d= -f2- | tr -d '\r')
    [[ -n "$v" ]] && echo "$v" || echo "$default"
}

OLLAMA_LLM_MODEL=$(read_env_var OLLAMA_LLM_MODEL "hermes3")
OLLAMA_EMBED_MODEL=$(read_env_var OLLAMA_EMBED_MODEL "nomic-embed-text")

# ─── Pretty output ────────────────────────────────────────────────────────────
BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; CYN=$'\033[36m'

step() { printf "\n${BOLD}${CYN}==> %s${RESET}\n" "$*"; }
ok()   { printf "${GRN}✓${RESET} %s\n" "$*"; }
warn() { printf "${YEL}!${RESET} %s\n" "$*"; }
die()  { printf "${RED}✗ %s${RESET}\n" "$*" >&2; exit 1; }

# ─── Open browser cross-platform ──────────────────────────────────────────────
open_browser() {
    local url="$1"
    if   command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
    elif command -v open     >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 &
    elif command -v start    >/dev/null 2>&1; then start "" "$url" >/dev/null 2>&1 &
    else
        printf "\n${BOLD}Open this URL in your browser:${RESET} %s\n" "$url"
    fi
}

# ─── Dependency check (POSIX bash only — used by start.sh / start.command) ───
ensure_ollama() {
    step "Checking Ollama…"
    if ! command -v ollama >/dev/null 2>&1; then
        die "Ollama is not installed. Download it from https://ollama.com/download and run this launcher again."
    fi
    ok "Ollama found at $(command -v ollama)"

    # Probe the server
    if ! curl -fsS -m 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
        warn "Ollama server is not responding. Trying to start it…"
        (ollama serve >/dev/null 2>&1 &) || true
        sleep 3
        if ! curl -fsS -m 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
            die "Ollama is installed but not running. Launch the Ollama app once, then re-run this script."
        fi
    fi
    ok "Ollama is running"
}

ensure_python() {
    step "Checking Python…"
    if ! command -v python3 >/dev/null 2>&1; then
        die "python3 not found. Install Python 3.10+ from https://www.python.org/downloads/"
    fi
    local ver
    ver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    ok "Python $ver"
}

ensure_node() {
    step "Checking Node.js…"
    if ! command -v node >/dev/null 2>&1; then
        die "Node.js not found. Install Node 18+ from https://nodejs.org/"
    fi
    if ! command -v npm >/dev/null 2>&1; then
        die "npm not found. Install Node.js (which includes npm) from https://nodejs.org/"
    fi
    local ver
    ver=$(node --version)
    ok "Node $ver"
}

pull_model() {
    local model="$1"
    step "Ensuring model '$model' is pulled…"
    if curl -fsS -m 3 "http://localhost:11434/api/tags" 2>/dev/null | grep -q "\"name\":\"$model"; then
        ok "Model '$model' already present"
    else
        printf "${DIM}Downloading $model — this can take a few minutes on first run…${RESET}\n"
        ollama pull "$model" || die "Failed to pull model '$model'. Try 'ollama pull $model' manually."
        ok "Model '$model' pulled"
    fi
}

setup_python_venv() {
    step "Setting up Python virtual environment…"
    if [[ ! -d "$PROJECT_ROOT/venv" ]]; then
        python3 -m venv "$PROJECT_ROOT/venv" || die "Failed to create virtual environment"
        ok "Created venv"
    else
        ok "venv already exists"
    fi
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/venv/bin/activate"
    pip install --quiet --upgrade pip || true
    pip install --quiet -r "$PROJECT_ROOT/requirements.txt" \
        || die "Failed to install Python requirements"
    ok "Python dependencies installed"
}

setup_npm_deps() {
    step "Installing frontend dependencies…"
    pushd "$PROJECT_ROOT/appliance-rag-ui" >/dev/null
    if [[ ! -d node_modules ]]; then
        npm install --no-audit --no-fund --loglevel=error \
            || die "Failed to install frontend dependencies"
        ok "npm packages installed"
    else
        ok "node_modules already present"
    fi
    popd >/dev/null
}

# ─── Wait for URL to be reachable ─────────────────────────────────────────────
wait_for_url() {
    local url="$1" label="$2" max=${3:-60}
    step "Waiting for $label at $url…"
    for ((i=1; i<=max; i++)); do
        if curl -fsS -m 2 "$url" >/dev/null 2>&1; then
            ok "$label is up"
            return 0
        fi
        sleep 1
    done
    die "$label did not become ready in ${max}s. Check the logs above."
}

# ─── PID tracking for clean shutdown ──────────────────────────────────────────
BACKEND_PID=""
FRONTEND_PID=""
cleanup() {
    printf "\n${YEL}Shutting down…${RESET}\n"
    [[ -n "$BACKEND_PID"  ]] && kill "$BACKEND_PID"  2>/dev/null && ok "Stopped backend"
    [[ -n "$FRONTEND_PID" ]] && kill "$FRONTEND_PID" 2>/dev/null && ok "Stopped frontend"
    # Give them a moment, then force-kill anything still hanging
    sleep 1
    pkill -f "uvicorn main:app"          2>/dev/null || true
    pkill -f "next dev"                  2>/dev/null || true
    exit 0
}
trap cleanup INT TERM EXIT
