# 🏭 Appliance Manual RAG

A local Retrieval-Augmented Generation (RAG) application that allows you to upload appliance manuals (PDF, DOCX, XLSX, TXT, MD) and chat with them. It runs completely locally using Ollama (LLM) and FastAPI (Backend) with a Next.js frontend, ensuring complete privacy. No data ever leaves your machine.

## Features
- **Local AI execution**: Completely offline after the initial setup.
- **Source Citations**: Every answer provides quoted excerpts and the exact page numbers from the manuals.
- **Easy Launchers**: One-click scripts to set up and start the application on Windows, macOS, and Linux.
- **LAN Deployment**: Built-in support to deploy on a local network server.

## How to Use

### 1. Prerequisites
- **Windows 10** (version 1803 or later)
- **Internet connection** for the first-time setup (~500 MB download)
- **8 GB RAM** minimum (16 GB recommended)
- **~10 GB free disk space** (for runtimes, models, and dependencies)

### 2. Install (one-time)
Double-click **[install.bat](file:///d:/projekti/Appliance-Manual-RAG/install.bat)** and wait for it to finish. This automatically downloads and sets up:
- Python 3.12 (portable — no system install needed)
- Node.js 20 (portable — no system install needed)
- Ollama (AI model runtime)
- All backend and frontend packages
- AI models (hermes3 + nomic-embed-text)

> **No manual installation of Python, Node.js, or Ollama is required.** The installer handles everything.

### 3. Start the Application
Double-click **[start.bat](file:///d:/projekti/Appliance-Manual-RAG/start.bat)** to launch. It will:
1. Start the Ollama AI server (if not already running).
2. Start the backend and frontend servers.
3. Open your browser to `http://localhost:3000`.

On **macOS/Linux**, use [start.command](file:///d:/projekti/Appliance-Manual-RAG/start.command) or [start.sh](file:///d:/projekti/Appliance-Manual-RAG/start.sh) (these still require manually installed Python, Node.js, and Ollama).

*Subsequent launches are fast — all dependencies are cached locally.*

### 4. Usage Steps
1. **Upload manuals**: In the left sidebar, click **Upload File** and select your manual. Wait for the "indexed" checkmark.
2. **Ask questions**: Type your question in the chat box at the bottom and press Enter.
3. **Verify answers**: Look at the source cards below the AI response to see exact page citations. Click them to view highlighted text excerpts.
4. **Manage files**: Hover over uploaded files in the sidebar to delete them individually, or click **Reset Everything** to clear all documents and start fresh.

---

### Detailed Documentation
- For detailed end-user troubleshooting and features, see the [User Guide (README_USERS.md)](file:///d:/projekti/Appliance-Manual-RAG/README_USERS.md).
- For local network deployment instructions on Linux, see the [Server Deployment Guide (README_SERVER.md)](file:///d:/projekti/Appliance-Manual-RAG/README_SERVER.md).
