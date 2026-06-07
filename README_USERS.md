# 🏭 Appliance Manual RAG — User Guide

**Chat with your appliance manuals.** Upload a PDF, ask a question, get a
specific answer with the exact page number and quoted text — all running
locally on your computer. No internet, no cloud, no data leaving your machine.

---

## What you need

- **A computer running Windows 10+, macOS 11+, or Linux** (any modern distro)
- **About 8 GB of free disk space** (for the AI model downloads)
- **8 GB of RAM minimum, 16 GB recommended**
- **An internet connection for the FIRST RUN only** — to download the AI model.
  After that, everything works offline.

That's it. No Python knowledge, no terminal skills, no command-line anything
required after the first install.

---

## Step 1 — Install Ollama (one time)

Ollama is the program that runs the AI on your computer. Pick your operating
system and follow the link:

| OS      | Download link                                                |
|---------|--------------------------------------------------------------|
| Windows | <https://ollama.com/download/windows>                        |
| macOS   | <https://ollama.com/download/mac>                            |
| Linux   | `curl -fsSL https://ollama.com/install.sh \| sh` in terminal |

After installing, **launch the Ollama app** — it adds an icon to your system
tray (Windows) or menu bar (macOS). Leave it running.

> 📷 *Screenshot placeholder — Ollama app running in the system tray*
> ![Ollama running in tray](docs/img/ollama-tray.png)

---

## Step 2 — Get the project

You have two options:

### Option A — Download as ZIP (easiest)

1. Go to the project page on GitHub
2. Click the green **Code** button → **Download ZIP**
3. Extract the ZIP somewhere you'll remember (e.g. Desktop or Documents)
4. **Important:** extract it to a folder whose path has NO SPACES, e.g.
   `C:\Users\YourName\Documents\Appliance-Manual-RAG` is fine,
   `C:\My Stuff\Project\Appliance Manual RAG` is not.

> 📷 *Screenshot placeholder — extracted folder in File Explorer*
> ![Extracted folder](docs/img/extracted-folder.png)

### Option B — Git clone (for the tech-curious)

```bash
git clone https://github.com/<your-org>/Appliance-Manual-RAG.git
cd Appliance-Manual-RAG
```

---

## Step 3 — Start the app

Just double-click the launcher for your operating system:

| OS      | File to double-click   |
|---------|------------------------|
| Windows | `start.bat`            |
| macOS   | `start.command`        |
| Linux   | `start.sh` (run once: `chmod +x start.sh`) |

A terminal/command-prompt window will open. The first time you run it,
it will:

1. Check that Ollama is installed
2. Download the AI model (`hermes3`, about 4 GB) and the embedding model
   (`nomic-embed-text`, about 270 MB) — this takes a few minutes
3. Create a Python virtual environment and install the backend libraries
4. Install the frontend's JavaScript dependencies
5. Start both servers in the background
6. Open your browser to the app

> 📷 *Screenshot placeholder — first-run launcher output*
> ![First run output](docs/img/first-run.png)

Subsequent runs are MUCH faster — only step 5 and 6.

> 📷 *Screenshot placeholder — app loaded in the browser*
> ![App loaded](docs/img/app-loaded.png)

---

## Step 4 — Use the app

### 4.1 Upload a document

1. Click **Upload File** in the left sidebar
2. Pick a PDF (or .docx, .xlsx, .txt, .md)
3. Wait for the "✅ indexed" message

> 📷 *Screenshot placeholder — uploading a PDF*
> ![Uploading](docs/img/upload.png)

### 4.2 Ask a question

Type into the box at the bottom and press **Enter** (or click **Send**).

> 📷 *Screenshot placeholder — asking a question*
> ![Asking](docs/img/ask.png)

The answer appears in the chat with:

- **The direct answer** in plain language
- **Quoted excerpts** from the document
- **Source cards** showing the file name and exact page number — click
  any source card to expand the highlighted excerpt

> 📷 *Screenshot placeholder — answer with sources*
> ![Answer with sources](docs/img/answer.png)

### 4.3 Try the suggested questions

If you don't know where to start, click any of the four suggested
questions on the empty chat screen.

### 4.4 Manage your documents

- **Remove one document**: hover over it in the sidebar and click the red ✕
- **Clear chat history** (keeps documents): click **💬 Clear Chat History**
- **Wipe everything** (delete all docs + chat): click **🧹 Reset Everything**

### 4.5 Switch models (optional)

The left sidebar shows a **Model** dropdown with all the AI models installed
locally. To actually switch, you need to edit `.env` and restart — see
"Advanced: switching models" below.

---

## Status indicators — what do they mean?

The left sidebar shows four small badges:

| Badge     | Green means…                    | Red means…                              |
|-----------|---------------------------------|-----------------------------------------|
| **Backend** | The Python server is running  | The Python server has crashed            |
| **Ollama**  | The Ollama app is running     | The Ollama app is not running            |
| **LLM**     | The chat model is downloaded  | The chat model hasn't been pulled yet    |
| **Embed**   | The embed model is downloaded | The embed model hasn't been pulled yet   |

If the **LLM** or **Embed** badge is red, the app will tell you exactly
which command to run. Open a terminal in the project folder and type:

```bash
ollama pull hermes3
ollama pull nomic-embed-text
```

---

## Troubleshooting

### "Ollama is not installed" error

You skipped step 1. Install Ollama, launch the app, then re-run the launcher.

### "Backend offline" in the sidebar

The Python server didn't start. Check the launcher window for an error
message. Common causes:

- **Port 8000 is already in use** — close any other app using port 8000,
  or change `BACKEND_PORT` in `.env`
- **Ollama isn't running** — launch the Ollama app

### "Cannot reach Ollama" in the sidebar

The Ollama app is installed but the server isn't running. Launch the
Ollama app from your Start menu / Applications folder.

### "Missing: hermes3" in the sidebar

Ollama is up but the model hasn't been pulled yet. Open a terminal in
the project folder and run:

```bash
ollama pull hermes3
```

…then refresh the page.

### The app is very slow

The first question on a freshly uploaded document is slow because the
AI has to "warm up". Subsequent questions are faster. Very large PDFs
(over 1000 pages) take a long time to index on upload.

### The answer says "not found in the uploaded documents"

Either:

- The answer genuinely isn't in the document — the AI is being honest
- The question is too vague — try a more specific question

### "Port 3000 is already in use" (Windows)

Another Next.js app is using port 3000. Edit `appliance-rag-ui\.env.local`
and set `FRONTEND_PORT=3001`, then restart.

### I want to uninstall

Just delete the project folder. Optionally, uninstall Ollama from your
system's app list. To free disk space, run `ollama rm hermes3 nomic-embed-text`.

---

## Where is my data stored?

Everything stays in the project folder:

- `documents/` — the files you uploaded
- `storage/` — the AI's index of those files
- `venv/` — the Python virtual environment (regeneratable)
- `appliance-rag-ui/node_modules/` — the frontend dependencies (regeneratable)
- `logs/` — log files (safe to delete)

The chat history is in your browser's `localStorage`, not on disk.
Clearing your browser data clears the chat.

---

## Advanced: switching models

By default the app uses `hermes3`. To use a different model:

1. Make sure it's pulled: `ollama pull <model-name>`
2. Open `.env` in the project root with any text editor
3. Change the line `OLLAMA_LLM_MODEL=hermes3` to your model, e.g.
   `OLLAMA_LLM_MODEL=llama3.1`
4. Save and re-run the launcher

The same applies to the embedding model — change `OLLAMA_EMBED_MODEL`.

---

## Need help?

Open an issue on the project's GitHub page with:

1. Your operating system and version
2. The exact text of any error message
3. A screenshot of the launcher window if possible
