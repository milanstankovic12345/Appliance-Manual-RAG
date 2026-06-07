# 🖥️ Appliance Manual RAG — Server Deployment Guide

Deploys the app on a Linux server so anyone on the LAN can use it from
their browser. Single port (80), two systemd services, automatic restarts.

> Looking for the end-user instructions? See [README_USERS.md](README_USERS.md).

---

## Architecture

```
   ┌──────────────────────────────────────────────────────────────────┐
   │                    Linux server (any distro)                     │
   │                                                                  │
   │   ┌────────────────┐    ┌─────────────────┐    ┌──────────────┐  │
   │   │  Ollama (LLM)  │    │  FastAPI :8000  │    │ Next.js :3000│  │
   │   │  port 11434    │◀──▶│  (uvicorn)      │◀──▶│ (next start) │  │
   │   └────────────────┘    └────────▲────────┘    └──────▲───────┘  │
   │                                  │                      │         │
   │                          ┌───────┴──────────────────────┴─────┐   │
   │                          │  Nginx :80 (reverse proxy)         │   │
   │                          │  /api/* → :8000,  / → :3000        │   │
   │                          └──────────────┬─────────────────────┘   │
   └─────────────────────────────────────────┼─────────────────────────┘
                                             │
                                ┌────────────▼────────────┐
                                │  Browser on the LAN     │
                                │  http://<server-ip>     │
                                └─────────────────────────┘
```

**Single port 80** means users don't need to remember different ports
and the deployment works behind corporate firewalls that only allow :80/:443.

---

## 1. Requirements

| Requirement   | Recommended                              |
|---------------|------------------------------------------|
| OS            | Ubuntu 22.04+ / Debian 12+ / RHEL 9+     |
| RAM           | 16 GB minimum (Hermes 3 needs ~5 GB)     |
| Disk          | 20 GB free (10 GB for models)            |
| CPU           | Modern x86_64 (Apple Silicon works too)  |
| GPU           | Optional but recommended for speed       |
| Network       | Static LAN IP or DNS hostname            |
| Privileges    | `sudo` access                            |

The deploy script supports `apt`, `dnf`, and `pacman` package managers
out of the box. For anything else, follow the manual install below.

---

## 2. Quick deploy (Ubuntu / Debian)

```bash
# 1. Get the code onto the server
git clone https://github.com/<your-org>/Appliance-Manual-RAG.git
cd Appliance-Manual-RAG

# 2. Make the script executable and run it as root
chmod +x deploy_server.sh
sudo ./deploy_server.sh
```

That's it. The script will:

1. Install Python 3, Node.js, Nginx, curl, ufw
2. Install Ollama and start the systemd service
3. Pull the `hermes3` and `nomic-embed-text` models
4. Create a `rag` system user
5. Copy the app to `/opt/appliance-rag`
6. Create a Python venv and install requirements
7. Build the Next.js frontend
8. Install and start two systemd services
9. Configure Nginx as a reverse proxy on port 80
10. Open the firewall
11. Print the LAN URL

Expected time on a fresh server: 5–15 minutes (mostly model download).

---

## 3. Verify the deployment

```bash
# Check service health
sudo systemctl status appliance-rag-backend
sudo systemctl status appliance-rag-frontend
sudo systemctl status nginx
sudo systemctl status ollama

# Check the backend health endpoint
curl -s http://localhost/health | python3 -m json.tool
```

You should see JSON like:

```json
{
    "backend": "ok",
    "ollama_reachable": true,
    "llm_model_available": true,
    "embed_model_available": true,
    "available_models": ["hermes3:latest", "nomic-embed-text:latest"],
    "index_ready": false,
    "document_count": 0
}
```

Now open `http://<server-lan-ip>` in a browser on another machine.

> Find the server's IP: `hostname -I` or `ip -4 addr show scope global`

---

## 4. Configuration

The deploy script creates `/opt/appliance-rag/.env`. To change settings:

```bash
sudo systemctl stop appliance-rag-backend appliance-rag-frontend
sudo nano /opt/appliance-rag/.env
sudo systemctl start appliance-rag-backend appliance-rag-frontend
```

Common variables:

| Variable             | Default                  | Purpose                            |
|----------------------|--------------------------|------------------------------------|
| `BACKEND_PORT`       | `8000`                   | Internal FastAPI port              |
| `OLLAMA_LLM_MODEL`   | `hermes3`                | Chat model (must be `ollama pull`ed) |
| `OLLAMA_EMBED_MODEL` | `nomic-embed-text`       | Embedding model                    |
| `ALLOWED_ORIGINS`    | `http://localhost,...`   | Comma-separated CORS origins       |

> ⚠️ After changing the model name, also run
> `ollama pull <new-model>` before restarting the backend.

---

## 5. Managing the services

```bash
# View live logs
sudo journalctl -u appliance-rag-backend -f
sudo journalctl -u appliance-rag-frontend -f

# Restart everything
sudo systemctl restart appliance-rag-backend appliance-rag-frontend nginx

# Disable from boot
sudo systemctl disable appliance-rag-backend appliance-rag-frontend
```

The services auto-restart on crash (`Restart=on-failure`) and start
automatically on server boot.

---

## 6. Updating the app

```bash
cd /opt/appliance-rag
sudo git pull         # or upload the new files via scp
sudo ./deploy_server.sh
```

`deploy_server.sh` is idempotent — it skips steps that are already done
and only re-pulls models / re-installs deps that have changed.

---

## 7. HTTPS (recommended for production)

This deployment serves plain HTTP. For production, add Let's Encrypt:

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.example.com
# Answer the prompts. Certbot edits /etc/nginx/sites-enabled/appliance-rag
# automatically and sets up auto-renewal.
```

Don't forget to open port 443 in the firewall:

```bash
sudo ufw allow 443/tcp
```

And add your HTTPS origin to `ALLOWED_ORIGINS` in `/opt/appliance-rag/.env`.

---

## 8. Backup and restore

The stateful bits to back up:

- `/opt/appliance-rag/documents/` — uploaded files
- `/opt/appliance-rag/storage/` — the vector index
- `/opt/appliance-rag/.env` — your config

```bash
# Backup
sudo tar czf appliance-rag-backup-$(date +%F).tar.gz \
    -C /opt appliance-rag/documents \
    -C /opt appliance-rag/storage \
    -C /opt appliance-rag/.env

# Restore
sudo systemctl stop appliance-rag-backend appliance-rag-frontend
sudo tar xzf appliance-rag-backup-<date>.tar.gz -C /
sudo systemctl start appliance-rag-backend appliance-rag-frontend
```

The Ollama model cache lives in `/usr/share/ollama` (Linux) and can be
backed up separately if disk space is a concern.

---

## 9. Manual install (unsupported distros)

If `deploy_server.sh` doesn't recognise your distro:

```bash
# 1. Install Ollama: https://ollama.com/download
# 2. Install Python 3.10+, Node 18+, Nginx
# 3. Place the project at /opt/appliance-rag, owned by a 'rag' user
# 4. Create a venv and install requirements:
sudo -u rag python3 -m venv /opt/appliance-rag/venv
sudo -u rag /opt/appliance-rag/venv/bin/pip install -r /opt/appliance-rag/requirements.txt
# 5. Build the frontend:
cd /opt/appliance-rag/appliance-rag-ui
sudo -u rag npm install
sudo -u rag npm run build
# 6. Copy the two .service files to /etc/systemd/system/
# 7. Copy nginx.conf to /etc/nginx/sites-available/appliance-rag and enable it
# 8. sudo systemctl daemon-reload && sudo systemctl enable --now appliance-rag-backend appliance-rag-frontend nginx
```

---

## 10. Troubleshooting

### "502 Bad Gateway" from Nginx

The frontend or backend service isn't running. Check:

```bash
sudo systemctl status appliance-rag-backend
sudo journalctl -u appliance-rag-backend -n 50
```

Common causes: Ollama not running, wrong port in `.env`, Python module
import error in the venv.

### Service starts then immediately dies

```bash
sudo journalctl -u appliance-rag-backend -n 100 --no-pager
```

Look for the last Python traceback. Most common: missing Python dep
(re-run `pip install -r requirements.txt`) or Ollama not running.

### Models download but `llm_model_available` is false

The deploy script pulls `hermes3` by default. If you changed
`OLLAMA_LLM_MODEL` to a different name in `.env` BEFORE running
`deploy_server.sh`, that name is what got pulled. Run
`ollama list` to see what's actually available.

### Out of disk space

Models are large. Check usage with `du -sh /usr/share/ollama`. Remove
unused models with `ollama rm <name>`.

### Server is slow / queries time out

- A CPU-only server doing its first query can take 30–60 seconds. Be patient.
- For faster responses, install Ollama on a machine with a GPU and
  point the backend at it: set `OLLAMA_BASE_URL=http://gpu-server:11434`
  in `.env` and ensure that machine's Ollama is listening on
  `0.0.0.0` (`OLLAMA_HOST=0.0.0.0 ollama serve`).

### Reset everything

```bash
sudo systemctl stop appliance-rag-backend appliance-rag-frontend
sudo rm -rf /opt/appliance-rag/storage/*
sudo rm -rf /opt/appliance-rag/documents/*
sudo systemctl start appliance-rag-backend appliance-rag-frontend
```
