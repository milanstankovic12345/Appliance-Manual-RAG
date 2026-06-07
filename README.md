# 🏭 Appliance Manual RAG

A local Retrieval-Augmented Generation (RAG) application that allows you to upload appliance manuals (PDF, DOCX, XLSX, TXT, MD) and chat with them. It runs completely locally using Ollama (LLM) and FastAPI (Backend) with a Next.js frontend, ensuring complete privacy. No data ever leaves your machine.

## Features
- **Local AI execution**: Completely offline after the initial setup.
- **Source Citations**: Every answer provides quoted excerpts and the exact page numbers from the manuals.
- **Easy Launchers**: One-click scripts to set up and start the application on Windows, macOS, and Linux.
- **LAN Deployment**: Built-in support to deploy on a local network server.

## How to Use

### 1. Prerequisites
- **Ollama**: Download and install [Ollama](https://ollama.com). Launch the app and make sure the tray icon is active.
- **System Requirements**: Minimum 8 GB RAM (16 GB recommended) and ~8 GB free disk space (to store the local LLM and embedding models).

### 2. Start the Application
Double-click the launcher script for your operating system:
- **Windows**: Run [start.bat](file:///d:/projekti/Appliance-Manual-RAG/start.bat)
- **macOS**: Run [start.command](file:///d:/projekti/Appliance-Manual-RAG/start.command)
- **Linux**: Run [start.sh](file:///d:/projekti/Appliance-Manual-RAG/start.sh) (make executable first: `chmod +x start.sh`)

On the first run, the launcher will:
1. Verify Ollama is running.
2. Pull the required models (`hermes3` and `nomic-embed-text`).
3. Set up a Python virtual environment and install backend requirements.
4. Install frontend JavaScript dependencies.
5. Start both servers in the background.
6. Open your browser to the web interface at `http://localhost:3000`.

*Subsequent launches will be much faster as dependencies and models are already downloaded.*

### 3. Usage Steps
1. **Upload manuals**: In the left sidebar, click **Upload File** and select your manual. Wait for the "indexed" checkmark.
2. **Ask questions**: Type your question in the chat box at the bottom and press Enter.
3. **Verify answers**: Look at the source cards below the AI response to see exact page citations. Click them to view highlighted text excerpts.
4. **Manage files**: Hover over uploaded files in the sidebar to delete them individually, or click **Reset Everything** to clear all documents and start fresh.

---

### Detailed Documentation
- For detailed end-user troubleshooting and features, see the [User Guide (README_USERS.md)](file:///d:/projekti/Appliance-Manual-RAG/README_USERS.md).
- For local network deployment instructions on Linux, see the [Server Deployment Guide (README_SERVER.md)](file:///d:/projekti/Appliance-Manual-RAG/README_SERVER.md).
