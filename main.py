import os
import shutil
import logging
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from dotenv import load_dotenv

from llama_index.core import (
    VectorStoreIndex,
    SimpleDirectoryReader,
    StorageContext,
    load_index_from_storage,
    Settings,
    PromptTemplate,
    get_response_synthesizer,
)
from llama_index.core.node_parser import SentenceSplitter
from llama_index.core.retrievers import VectorIndexRetriever
from llama_index.core.query_engine import RetrieverQueryEngine
from llama_index.llms.ollama import Ollama
from llama_index.embeddings.ollama import OllamaEmbedding

# ─────────────────────────────────────────────────────────────────────────────
# Configuration — values come from .env (or environment), with safe defaults.
# ─────────────────────────────────────────────────────────────────────────────
load_dotenv()

BACKEND_HOST = os.getenv("BACKEND_HOST", "0.0.0.0")
BACKEND_PORT = int(os.getenv("BACKEND_PORT", "8000"))

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_LLM_MODEL = os.getenv("OLLAMA_LLM_MODEL", "hermes3")
OLLAMA_EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
OLLAMA_REQUEST_TIMEOUT = float(os.getenv("OLLAMA_REQUEST_TIMEOUT", "360"))

DOCS_DIR = Path(os.getenv("DOCS_DIR", "./documents"))
STORAGE_DIR = Path(os.getenv("STORAGE_DIR", "./storage"))
DOCS_DIR.mkdir(exist_ok=True)
STORAGE_DIR.mkdir(exist_ok=True)

# Comma-separated list of allowed browser origins for CORS.
ALLOWED_ORIGINS = [
    o.strip() for o in os.getenv(
        "ALLOWED_ORIGINS",
        "http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000",
    ).split(",") if o.strip()
]

SUPPORTED_EXTENSIONS = {".pdf", ".docx", ".txt", ".md", ".xlsx"}

# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(asctime)s — %(levelname)s — %(message)s")
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# FastAPI app
# ─────────────────────────────────────────────────────────────────────────────
app = FastAPI(title="Document RAG API", version="2.1")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─────────────────────────────────────────────────────────────────────────────
# LLM Configuration
# System prompt tells Hermes to be specific and always cite sources.
# ─────────────────────────────────────────────────────────────────────────────
Settings.llm = Ollama(
    model=OLLAMA_LLM_MODEL,
    base_url=OLLAMA_BASE_URL,
    request_timeout=OLLAMA_REQUEST_TIMEOUT,
    system_prompt=(
        "You are a precise technical document assistant for a company. "
        "You answer questions using ONLY the document excerpts provided to you. "
        "Rules you must follow without exception:\n"
        "1. Always quote the exact relevant sentence(s) from the document.\n"
        "2. Always cite the source file name and page number.\n"
        "3. Never give a generic answer — be specific and detailed.\n"
        "4. If the answer is not in the documents, say so explicitly.\n"
        "5. Format citations as: [Source: <filename>, Page <number>]"
    ),
)

# ─────────────────────────────────────────────────────────────────────────────
# Embedding Model
# ─────────────────────────────────────────────────────────────────────────────
Settings.embed_model = OllamaEmbedding(
    model_name=OLLAMA_EMBED_MODEL,
    base_url=OLLAMA_BASE_URL,
)

# ─────────────────────────────────────────────────────────────────────────────
# Chunking Strategy
#
# chunk_size=400  — roughly one paragraph. Smaller = more precise retrieval.
#                   Default was 1024 which mixed unrelated content into one chunk.
# chunk_overlap=80 — 20% overlap prevents losing context at chunk boundaries
#                    (e.g. a sentence that spans two chunks still gets retrieved).
# ─────────────────────────────────────────────────────────────────────────────
Settings.node_parser = SentenceSplitter(
    chunk_size=400,
    chunk_overlap=80,
)

# ─────────────────────────────────────────────────────────────────────────────
# Prompts
#
# These templates are injected into the Hermes context window as the
# "instructions + retrieved chunks" block. The metadata LlamaIndex attaches
# to each chunk (file_name, page_label) is included automatically in context_str.
# ─────────────────────────────────────────────────────────────────────────────
CITATION_QA_PROMPT = PromptTemplate(
    "You are a precise document assistant for a company.\n"
    "Answer using ONLY the excerpts below. Do not use outside knowledge.\n\n"
    "REQUIRED FORMAT:\n"
    "• Start with a direct, specific answer in plain language.\n"
    "• Quote the exact relevant sentence(s) from the document in double quotes.\n"
    "• End every cited fact with: [Source: <file name>, Page <number>]\n"
    "• If multiple excerpts support the answer, cite all of them.\n"
    "• If the answer is NOT present in any excerpt, respond with:\n"
    "  'This information was not found in the uploaded documents. "
    "Please check the document directly or contact the responsible department.'\n\n"
    "Document excerpts (each includes file name and page number):\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    "{context_str}\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    "Question: {query_str}\n\n"
    "Specific answer with citations:"
)

REFINE_PROMPT = PromptTemplate(
    "Original question: {query_str}\n\n"
    "Current answer (may be incomplete):\n{existing_answer}\n\n"
    "Additional document excerpts:\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    "{context_msg}\n"
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    "Refine the answer using any new relevant information from these excerpts. "
    "Keep all existing citations. Add new [Source: file, Page] citations where appropriate. "
    "Do not remove specific details already in the answer.\n\n"
    "Refined answer:"
)

# ─────────────────────────────────────────────────────────────────────────────
# Index state
# ─────────────────────────────────────────────────────────────────────────────
index: Optional[VectorStoreIndex] = None


def get_all_docs() -> list[Path]:
    return [f for f in DOCS_DIR.iterdir() if f.suffix.lower() in SUPPORTED_EXTENSIONS]


def rebuild_index() -> None:
    """Re-index every document in DOCS_DIR from scratch."""
    global index
    files = get_all_docs()
    if not files:
        index = None
        logger.info("No documents found — index cleared.")
        return

    logger.info(f"Indexing {len(files)} file(s): {[f.name for f in files]}")

    documents = SimpleDirectoryReader(
        str(DOCS_DIR),
        filename_as_id=True,
        required_exts=list(SUPPORTED_EXTENSIONS),
    ).load_data(show_progress=True)

    # Log a metadata sample so we can verify page numbers are being captured
    if documents:
        logger.info(f"Sample node metadata: {documents[0].metadata}")

    index = VectorStoreIndex.from_documents(documents, show_progress=True)
    index.storage_context.persist(persist_dir=str(STORAGE_DIR))
    logger.info(f"Index built and persisted. Total chunks: {len(index.docstore.docs)}")


def try_load_index() -> None:
    """Load persisted index from disk on startup."""
    global index
    if (STORAGE_DIR / "docstore.json").exists():
        try:
            ctx = StorageContext.from_defaults(persist_dir=str(STORAGE_DIR))
            index = load_index_from_storage(ctx)
            logger.info(f"Loaded index from disk. Chunks: {len(index.docstore.docs)}")
        except Exception as e:
            logger.warning(f"Could not load saved index ({e}). Will rebuild on next upload.")
    else:
        logger.info("No saved index found — upload documents to begin.")


try_load_index()


# ─────────────────────────────────────────────────────────────────────────────
# Ollama helpers (used by /health and /models)
# ─────────────────────────────────────────────────────────────────────────────

def _ollama_get(path: str, timeout: float = 5.0):
    """GET against the Ollama HTTP API. Returns parsed JSON or raises."""
    import urllib.request
    import urllib.error
    import json as _json
    req = urllib.request.Request(f"{OLLAMA_BASE_URL}{path}")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return _json.loads(r.read().decode("utf-8"))


def list_ollama_models() -> list[dict]:
    """Return Ollama's list of locally available models."""
    try:
        data = _ollama_get("/api/tags")
        return data.get("models", [])
    except Exception as e:
        logger.warning(f"Could not list Ollama models: {e}")
        return []


# ─────────────────────────────────────────────────────────────────────────────
# API Models
# ─────────────────────────────────────────────────────────────────────────────

class QueryRequest(BaseModel):
    question: str
    top_k: int = 8


class SourceNode(BaseModel):
    file: str
    page: str
    score: Optional[float] = None
    snippet: str


class QueryResponse(BaseModel):
    answer: str
    sources: list[SourceNode]
    chunks_searched: int


class DocumentInfo(BaseModel):
    name: str
    size_kb: float
    extension: str


class StatusResponse(BaseModel):
    document_count: int
    documents: list[DocumentInfo]
    index_ready: bool
    total_chunks: int
    current_model: str
    embed_model: str


class HealthResponse(BaseModel):
    backend: str
    ollama_reachable: bool
    ollama_url: str
    llm_model_configured: str
    llm_model_available: bool
    embed_model_configured: str
    embed_model_available: bool
    available_models: list[str]
    index_ready: bool
    document_count: int


# ─────────────────────────────────────────────────────────────────────────────
# Endpoints
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/health", response_model=HealthResponse)
async def health():
    """
    Real health check: verifies backend is up AND Ollama is reachable AND
    the configured LLM and embedding models are both pulled.
    Returns 503 if any required component is missing.
    """
    models = list_ollama_models()
    available_names = {m.get("name", "").split(":")[0] for m in models}

    # Ollama tags are reported as 'name:tag' (e.g. 'hermes3:latest'); allow
    # the user to specify either bare name or name:tag in OLLAMA_LLM_MODEL.
    def _is_available(configured: str) -> bool:
        if not configured:
            return False
        bare = configured.split(":")[0]
        return (
            configured in {m.get("name", "") for m in models}
            or bare in available_names
        )

    llm_ok = _is_available(OLLAMA_LLM_MODEL)
    embed_ok = _is_available(OLLAMA_EMBED_MODEL)
    ollama_ok = len(models) >= 0  # [] is still a valid response — connection worked

    body = HealthResponse(
        backend="ok",
        ollama_reachable=ollama_ok,
        ollama_url=OLLAMA_BASE_URL,
        llm_model_configured=OLLAMA_LLM_MODEL,
        llm_model_available=llm_ok,
        embed_model_configured=OLLAMA_EMBED_MODEL,
        embed_model_available=embed_ok,
        available_models=sorted({m.get("name", "") for m in models}),
        index_ready=index is not None,
        document_count=len(get_all_docs()),
    )

    if not ollama_ok or not llm_ok or not embed_ok:
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=503, content=body.model_dump())
    return body


@app.get("/status", response_model=StatusResponse)
async def status():
    files = get_all_docs()
    doc_infos = [
        DocumentInfo(
            name=f.name,
            size_kb=round(f.stat().st_size / 1024, 1),
            extension=f.suffix.lower(),
        )
        for f in files
    ]
    return StatusResponse(
        document_count=len(files),
        documents=doc_infos,
        index_ready=index is not None,
        total_chunks=len(index.docstore.docs) if index else 0,
        current_model=OLLAMA_LLM_MODEL,
        embed_model=OLLAMA_EMBED_MODEL,
    )


@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    suffix = Path(file.filename).suffix.lower()
    if suffix not in SUPPORTED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"File type '{suffix}' is not supported. Accepted: {', '.join(sorted(SUPPORTED_EXTENSIONS))}",
        )

    dest = DOCS_DIR / file.filename
    replaced = dest.exists()
    with open(dest, "wb") as buf:
        shutil.copyfileobj(file.file, buf)
    logger.info(f"Saved '{file.filename}' ({dest.stat().st_size // 1024} KB){' (replaced existing)' if replaced else ''}")

    # Always wipe old storage so new chunking settings take full effect
    if STORAGE_DIR.exists():
        shutil.rmtree(STORAGE_DIR)
    STORAGE_DIR.mkdir()

    try:
        rebuild_index()
    except Exception as e:
        logger.error(f"Indexing error: {e}")
        raise HTTPException(status_code=500, detail=f"File saved but indexing failed: {e}")

    return {
        "message": f"'{file.filename}' uploaded and indexed." + (" (replaced existing file)" if replaced else ""),
        "replaced": replaced,
        "total_documents": len(get_all_docs()),
        "total_chunks": len(index.docstore.docs) if index else 0,
    }


@app.get("/documents/{filename}/view")
async def view_document(filename: str):
    target = DOCS_DIR / filename
    if not target.exists():
        raise HTTPException(status_code=404, detail=f"'{filename}' not found.")
    return FileResponse(target)


@app.delete("/documents/{filename}")
async def delete_document(filename: str):
    target = DOCS_DIR / filename
    if not target.exists():
        raise HTTPException(status_code=404, detail=f"'{filename}' not found.")
    target.unlink()
    logger.info(f"Deleted '{filename}'. Rebuilding index…")

    if STORAGE_DIR.exists():
        shutil.rmtree(STORAGE_DIR)
    STORAGE_DIR.mkdir()
    rebuild_index()

    return {"message": f"'{filename}' removed and index rebuilt."}


@app.post("/reset")
async def reset_all():
    """Wipe all uploaded documents and the persisted index."""
    deleted = 0
    for f in get_all_docs():
        try:
            f.unlink()
            deleted += 1
        except Exception as e:
            logger.warning(f"Failed to delete {f}: {e}")

    if STORAGE_DIR.exists():
        shutil.rmtree(STORAGE_DIR)
    STORAGE_DIR.mkdir()
    rebuild_index()  # rebuild_index() handles the empty case

    global index
    index = None
    return {"message": f"Reset complete. Removed {deleted} document(s).", "documents_remaining": 0}


@app.post("/query", response_model=QueryResponse)
async def query(req: QueryRequest):
    if index is None:
        raise HTTPException(
            status_code=400,
            detail="No documents indexed. Upload at least one file first.",
        )

    top_k = max(4, min(req.top_k, 15))

    try:
        # Build retriever + synthesizer separately so we can control each
        retriever = VectorIndexRetriever(index=index, similarity_top_k=top_k)
        synthesizer = get_response_synthesizer(
            text_qa_template=CITATION_QA_PROMPT,
            refine_template=REFINE_PROMPT,
            response_mode="compact",
            verbose=False,
        )
        engine = RetrieverQueryEngine(
            retriever=retriever,
            response_synthesizer=synthesizer,
        )

        response = engine.query(req.question)

        # Build deduplicated source list with page number + snippet
        seen: set[str] = set()
        sources: list[SourceNode] = []

        for node in response.source_nodes:
            meta = node.metadata or {}
            file_name = meta.get("file_name") or meta.get("filename") or "Unknown"

            # LlamaIndex uses "page_label" for PDF pages (from pypdf)
            page = (
                str(meta.get("page_label", ""))
                or str(meta.get("page", ""))
                or "N/A"
            )

            dedup_key = f"{file_name}::{page}"
            if dedup_key in seen:
                continue
            seen.add(dedup_key)

            raw = node.text.strip()
            snippet = raw[:350] + ("…" if len(raw) > 350 else "")

            sources.append(SourceNode(
                file=file_name,
                page=page,
                score=round(float(node.score), 3) if node.score is not None else None,
                snippet=snippet,
            ))

        return QueryResponse(
            answer=str(response),
            sources=sources,
            chunks_searched=len(response.source_nodes),
        )

    except Exception as e:
        logger.error(f"Query failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Query error: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# Entry point for `python main.py` (the launchers also call uvicorn directly)
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    logger.info(f"Starting backend on http://{BACKEND_HOST}:{BACKEND_PORT}")
    uvicorn.run("main:app", host=BACKEND_HOST, port=BACKEND_PORT, reload=False)
