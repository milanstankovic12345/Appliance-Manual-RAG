# Appliance Manual RAG — UI

This is the Next.js 16 frontend for the Appliance Manual RAG project.

For full instructions, see the top-level project files:

- **[README_USERS.md](../README_USERS.md)** — end-user guide (double-click to run)
- **[README_SERVER.md](../README_SERVER.md)** — server deployment guide

## Local development

```bash
# From the project root
./start.sh          # Linux / macOS
start.bat           # Windows
```

Or, to run the UI in isolation:

```bash
cd appliance-rag-ui
cp .env.example .env.local       # set NEXT_PUBLIC_API_URL=http://localhost:8000
npm install
npm run dev
```

## Build for production

```bash
NEXT_PUBLIC_API_URL= npm run build
npm start
```

> When running behind the nginx reverse proxy (LAN deployment), set
> `NEXT_PUBLIC_API_URL=` (empty) so the browser uses the page's own
> origin and Nginx can route `/api/*` correctly.
