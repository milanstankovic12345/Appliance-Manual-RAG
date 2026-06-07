#!/usr/bin/env bash
# macOS launcher for Appliance Manual RAG.
# The .command extension lets Finder execute this on double-click.
# A Terminal window will open to keep the servers running.

set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/scripts/_common.sh"

printf "${BOLD}🏭 Appliance Manual RAG — macOS launcher${RESET}\n"

ensure_ollama
ensure_python
ensure_node
pull_model "$OLLAMA_LLM_MODEL"
pull_model "$OLLAMA_EMBED_MODEL"
setup_python_venv
setup_npm_deps

# ─── Start backend ────────────────────────────────────────────────────────────
step "Starting backend on port $BACKEND_PORT…"
source "$PROJECT_ROOT/venv/bin/activate"
cd "$PROJECT_ROOT"
mkdir -p "$PROJECT_ROOT/logs"
nohup python3 -m uvicorn main:app --host 0.0.0.0 --port "$BACKEND_PORT" \
    > "$PROJECT_ROOT/logs/backend.log" 2>&1 &
BACKEND_PID=$!
ok "Backend started (pid $BACKEND_PID) — logs: logs/backend.log"

# ─── Start frontend ───────────────────────────────────────────────────────────
step "Starting frontend on port $FRONTEND_PORT…"
pushd "$PROJECT_ROOT/appliance-rag-ui" >/dev/null
nohup npm run dev -- --port "$FRONTEND_PORT" \
    > "$PROJECT_ROOT/logs/frontend.log" 2>&1 &
FRONTEND_PID=$!
popd >/dev/null
ok "Frontend started (pid $FRONTEND_PID) — logs: logs/frontend.log"

# ─── Wait + open browser ──────────────────────────────────────────────────────
wait_for_url "http://localhost:$BACKEND_PORT/health" "Backend" 60
wait_for_url "http://localhost:$FRONTEND_PORT"        "Frontend" 90

printf "\n${BOLD}${GRN}🎉 App is running!${RESET}\n"
printf "  Backend:  ${CYN}http://localhost:%s${RESET}\n" "$BACKEND_PORT"
printf "  Frontend: ${CYN}http://localhost:%s${RESET}\n" "$FRONTEND_PORT"
printf "\n${DIM}Press Ctrl+C in this window to stop both servers.${RESET}\n"
printf "${DIM}Closing this window will leave the servers running in the background.${RESET}\n"

open_browser "http://localhost:$FRONTEND_PORT"

# Block until interrupted
wait
