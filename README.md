# 🏭 Appliance Manual RAG

A Retrieval-Augmented Generation (RAG) application that allows you to upload appliance manuals (PDF, DOCX, XLSX, TXT, MD) and chat with them. It uses Ollama for local LLM inference and FastAPI for the backend, with a Next.js frontend. 

This repository has been structured for clean, production-ready deployment on an Ubuntu Linux server.

## Project Structure

```
/app
├── backend/            # FastAPI Python backend
├── frontend/           # Next.js web interface
├── infrastructure/     # Nginx config, systemd templates, scripts
├── data/               # Documents, storage/vector-index, and logs
├── deploy.sh           # Automated Ubuntu deployment script
```

## Server Deployment (Ubuntu)

The repository includes a comprehensive deployment script that installs all dependencies, configures systemd services, sets up Nginx as a reverse proxy, and configures Ollama.

### Prerequisites

- Ubuntu/Debian server
- Root (sudo) access

### Quick Start

1. Clone or copy the repository to your server (e.g., `/opt/appliance-rag`).
2. Make the deployment script executable:
   ```bash
   chmod +x deploy.sh
   ```
3. Run the deployment script with sudo:
   ```bash
   sudo ./deploy.sh
   ```

The script will:
- Install Python, Node.js, and Nginx.
- Install Ollama and pull the required models (`hermes3` and `nomic-embed-text`).
- Create a Python virtual environment and install backend dependencies.
- Build the Next.js frontend.
- Create and start systemd services (`appliance-rag-backend` and `appliance-rag-frontend`).
- Configure Nginx and open the firewall on port 80.

## Usage

1. Open your browser and navigate to the server's IP address or hostname.
2. **Upload manuals**: Click **Upload File** in the sidebar.
3. **Ask questions**: Type your question in the chat box at the bottom. The AI will provide answers using ONLY the uploaded manuals, citing exact pages.
4. **Manage files**: You can delete individual files or use **Reset Everything** to clear all documents and start fresh.

## Managing the Services

You can manage the application using standard systemd commands:

```bash
sudo systemctl status appliance-rag-backend
sudo systemctl status appliance-rag-frontend
sudo journalctl -u appliance-rag-backend -f
```

To update the application:
```bash
git pull
sudo ./deploy.sh
```
