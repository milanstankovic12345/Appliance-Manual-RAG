"use client";

import { useState, useRef, useEffect, useCallback } from "react";

// ── Config ────────────────────────────────────────────────────────────────────

// NEXT_PUBLIC_API_URL must be set at build time. If empty, fall back to the
// page's own origin (works behind a reverse proxy with no /api prefix).
const RAW_API = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
const API = RAW_API.replace(/\/+$/, "");
const CHAT_STORAGE_KEY = "appliance-rag-chat-v1";

// ── Types ─────────────────────────────────────────────────────────────────────

type Role = "user" | "assistant";

interface Source {
  file: string;
  page: string;
  score: number | null;
  snippet: string;
}

interface Message {
  role: Role;
  content: string;
  sources?: Source[];
  chunks_searched?: number;
  error?: boolean;
  ts: number;
}

interface DocInfo {
  name: string;
  size_kb: number;
  extension: string;
}

interface Status {
  document_count: number;
  documents: DocInfo[];
  index_ready: boolean;
  total_chunks: number;
  current_model: string;
  embed_model: string;
}

interface HealthData {
  backend: string;
  ollama_reachable: boolean;
  ollama_url: string;
  llm_model_configured: string;
  llm_model_available: boolean;
  embed_model_configured: string;
  embed_model_available: boolean;
  available_models: string[];
  index_ready: boolean;
  document_count: number;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function extIcon(ext: string) {
  const map: Record<string, string> = {
    ".pdf": "📄",
    ".docx": "📝",
    ".xlsx": "📊",
    ".txt": "📃",
    ".md": "📋",
  };
  return map[ext] ?? "📁";
}

function scoreBar(score: number | null) {
  if (score === null) return null;
  const pct = Math.round(score * 100);
  const color =
    pct >= 75 ? "bg-green-500" : pct >= 50 ? "bg-yellow-500" : "bg-orange-500";
  return (
    <div className="flex items-center gap-2 mt-1">
      <div className="flex-1 h-1.5 bg-slate-200 dark:bg-gray-700 rounded-full overflow-hidden">
        <div className={`h-full ${color} rounded-full`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-xs text-slate-400 dark:text-gray-400 font-mono w-8 text-right">{pct}%</span>
    </div>
  );
}

function loadStoredChat(): Message[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(CHAT_STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    // Defensive: ensure every message has a timestamp
    return parsed.map((m: Partial<Message>) => ({ ...m, ts: m.ts ?? Date.now() } as Message));
  } catch {
    return [];
  }
}

// ── Source Card component ─────────────────────────────────────────────────────

function SourceCard({ source }: { source: Source }) {
  const hasPage = source.page && source.page !== "N/A";
  const ext = source.file.split(".").pop()?.toLowerCase() || "";
  const isPdf = ext === "pdf";

  const href = `${API}/documents/${encodeURIComponent(source.file)}/view${hasPage ? `#page=${source.page}` : ""}`;

  const handleClick = (e: React.MouseEvent<HTMLAnchorElement>) => {
    if (!isPdf) {
      e.preventDefault();
      alert("Only PDF files can be opened directly. This file is a " + ext.toUpperCase() + " file.");
    }
  };

  return (
    <div className="border border-slate-200 dark:border-gray-700 rounded-lg overflow-hidden text-xs shadow-xs">
      <a
        href={href}
        target="_blank"
        rel="noopener noreferrer"
        onClick={handleClick}
        className="w-full flex items-start gap-2 px-3 py-2 bg-slate-50/50 hover:bg-slate-100 transition-colors text-left dark:bg-gray-800/60 dark:hover:bg-gray-800"
      >
        <span className="mt-0.5 shrink-0">{extIcon(`.${ext}`)}</span>
        <div className="flex-1 min-w-0">
          <p className="text-slate-800 dark:text-gray-200 font-medium truncate">{source.file}</p>
          <p className="text-blue-600 dark:text-blue-400 mt-0.5 font-medium">
            📍 Page&nbsp;
            <span className="font-bold">{hasPage ? source.page : "—"}</span>
            <span className="text-slate-400 dark:text-gray-500 font-normal"> · click to open file</span>
          </p>
          {scoreBar(source.score)}
        </div>
      </a>
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

export default function Home() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [uploadMsg, setUploadMsg] = useState("");
  const [status, setStatus] = useState<Status | null>(null);
  const [health, setHealth] = useState<HealthData | null>(null);
  const [backendOk, setBackendOk] = useState<boolean | null>(null);
  const [deletingFile, setDeletingFile] = useState<string | null>(null);
  const [resetting, setResetting] = useState(false);
  const [mounted, setMounted] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  // Theme support
  const [theme, setTheme] = useState<"light" | "dark">("dark");

  // ── Hydrate chat and theme from localStorage on mount ───────────────────────
  useEffect(() => {
    setMounted(true);
    setMessages(loadStoredChat());

    const savedTheme = window.localStorage.getItem("appliance-rag-theme") as "light" | "dark" | null;
    if (savedTheme === "light" || savedTheme === "dark") {
      setTheme(savedTheme);
    } else {
      const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
      setTheme(systemDark ? "dark" : "light");
    }
  }, []);

  const toggleTheme = () => {
    const nextTheme = theme === "dark" ? "light" : "dark";
    setTheme(nextTheme);
    window.localStorage.setItem("appliance-rag-theme", nextTheme);
  };

  // ── Persist chat on every change ──────────────────────────────────────────
  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      // Cap stored history to last 200 messages to avoid blowing past quota
      const trimmed = messages.slice(-200);
      window.localStorage.setItem(CHAT_STORAGE_KEY, JSON.stringify(trimmed));
    } catch {
      // Ignore quota errors
    }
  }, [messages]);

  // ── Backend health + status ───────────────────────────────────────────────

  const fetchStatus = useCallback(async () => {
    try {
      const r = await fetch(`${API}/status`);
      if (r.ok) setStatus(await r.json());
    } catch { }
  }, []);

  const fetchHealth = useCallback(async () => {
    try {
      const r = await fetch(`${API}/health`);
      // 503 is a valid response with a JSON body — read it either way
      const data = await r.json();
      setHealth(data);
      setBackendOk(r.ok);
      if (r.ok) fetchStatus();
    } catch {
      setBackendOk(false);
    }
  }, [fetchStatus]);

  useEffect(() => {
    fetchHealth();
    // Periodic health polling so the user notices if Ollama goes down
    const t = setInterval(fetchHealth, 15000);
    return () => clearInterval(t);
  }, [fetchHealth]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, loading]);

  // ── Upload ────────────────────────────────────────────────────────────────

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setUploadMsg(`Uploading ${file.name}…`);
    const form = new FormData();
    form.append("file", file);
    try {
      const r = await fetch(`${API}/upload`, { method: "POST", body: form });
      const data = await r.json();
      if (r.ok) {
        setUploadMsg(`✅ ${data.message} (${data.total_chunks} chunks indexed)`);
        await fetchStatus();
        await fetchHealth();
      } else {
        setUploadMsg(`❌ ${data.detail}`);
      }
    } catch {
      setUploadMsg("❌ Upload failed. Is the backend running?");
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  // ── Delete document ────────────────────────────────────────────────────────

  async function handleDelete(filename: string) {
    if (!confirm(`Delete "${filename}" and rebuild the index?`)) return;
    setDeletingFile(filename);
    try {
      const r = await fetch(`${API}/documents/${encodeURIComponent(filename)}`, {
        method: "DELETE",
      });
      const data = await r.json();
      if (r.ok) {
        setUploadMsg(`🗑️ ${data.message}`);
        await fetchStatus();
      } else {
        setUploadMsg(`❌ ${data.detail}`);
      }
    } catch {
      setUploadMsg("❌ Delete failed.");
    } finally {
      setDeletingFile(null);
    }
  }

  // ── Reset all (wipe docs + chat) ──────────────────────────────────────────

  async function handleReset() {
    if (!confirm("This will delete ALL uploaded documents and the chat history. Continue?")) return;
    setResetting(true);
    try {
      const r = await fetch(`${API}/reset`, { method: "POST" });
      const data = await r.json();
      if (r.ok) {
        setUploadMsg(`🧹 ${data.message}`);
        setMessages([]);            // wipe chat
        setInput("");
        await fetchStatus();
      } else {
        setUploadMsg(`❌ ${data.detail}`);
      }
    } catch {
      setUploadMsg("❌ Reset failed.");
    } finally {
      setResetting(false);
    }
  }

  // ── Clear chat only (keep docs) ───────────────────────────────────────────

  function handleClearChat() {
    if (messages.length === 0) return;
    if (!confirm("Clear chat history? Your documents will stay indexed.")) return;
    setMessages([]);
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  async function handleSend() {
    const question = input.trim();
    if (!question || loading) return;
    setInput("");
    const userMsg: Message = { role: "user", content: question, ts: Date.now() };
    setMessages((prev) => [...prev, userMsg]);
    setLoading(true);
    try {
      const r = await fetch(`${API}/query`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, top_k: 8 }),
      });
      const data = await r.json();
      if (r.ok) {
        setMessages((prev) => [
          ...prev,
          {
            role: "assistant",
            content: data.answer,
            sources: data.sources,
            chunks_searched: data.chunks_searched,
            ts: Date.now(),
          },
        ]);
      } else {
        setMessages((prev) => [
          ...prev,
          { role: "assistant", content: data.detail, error: true, ts: Date.now() },
        ]);
      }
    } catch {
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          content: "Cannot reach the backend. Make sure the Python server is running.",
          error: true,
          ts: Date.now(),
        },
      ]);
    } finally {
      setLoading(false);
    }
  }

  // ── Derived state ─────────────────────────────────────────────────────────

  const ollamaOk = health?.ollama_reachable ?? false;
  const llmOk = health?.llm_model_available ?? false;
  const embedOk = health?.embed_model_available ?? false;
  const allOk = !!backendOk && ollamaOk && llmOk && embedOk;

  // ── Render ────────────────────────────────────────────────────────────────

  if (!mounted) return null;

  return (
    <div className={`${theme} w-full h-full`}>
      <div className="flex h-screen bg-slate-50 dark:bg-gray-950 text-slate-800 dark:text-gray-100 font-sans overflow-hidden">

        {/* ── Left Sidebar ─────────────────────────────────────────────────── */}
        <aside className="w-72 flex-shrink-0 bg-white dark:bg-gray-900 border-r border-slate-200 dark:border-gray-800 flex flex-col">

          {/* Header */}
          <div className="p-5 border-b border-slate-100 dark:border-gray-800 flex items-center justify-between">
            <div>
              <h1 className="text-base font-bold text-slate-900 dark:text-white">🏭 Document AI</h1>
              <p className="text-xs text-slate-500 dark:text-gray-400 mt-0.5">Powered by Hermes 3</p>
            </div>
            <button
              onClick={toggleTheme}
              className="p-1.5 rounded-lg border border-slate-200 dark:border-gray-800 hover:bg-slate-100 dark:hover:bg-gray-800 text-slate-600 dark:text-gray-300 transition-colors"
              title={theme === "dark" ? "Switch to light theme" : "Switch to dark theme"}
            >
              {theme === "dark" ? "☀️" : "🌙"}
            </button>
          </div>

          {/* Backend / Ollama / model status badges */}
          <div className="px-4 pt-4 space-y-1.5">
            <StatusBadge
              label="Backend"
              ok={!!backendOk}
              loading={backendOk === null}
              okText="API online"
              failText="API offline"
            />
            <StatusBadge
              label="LLM"
              ok={llmOk}
              loading={false}
              okText={health?.llm_model_configured ?? "—"}
              failText={`Missing: ${health?.llm_model_configured ?? "—"}`}
            />
          </div>

          {/* Upload */}
          <div className="px-4 pt-4 space-y-2">
            <p className="text-[11px] font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wider">
              Add Document
            </p>
            <button
              onClick={() => fileRef.current?.click()}
              disabled={uploading || !allOk}
              className="w-full bg-blue-600 hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-sm font-medium rounded-lg px-4 py-2 transition-colors"
            >
              {uploading ? "Uploading…" : "Upload File"}
            </button>
            {/* Accept PDF, DOCX, XLSX, TXT, MD */}
            <input
              ref={fileRef}
              type="file"
              accept=".pdf,.docx,.txt,.md,.xlsx"
              className="hidden"
              onChange={handleUpload}
            />
            <p className="text-[10px] text-slate-400 dark:text-gray-500">PDF · DOCX · XLSX · TXT · MD</p>
            {uploadMsg && (
              <p className="text-xs text-slate-700 dark:text-gray-300 break-words leading-relaxed">{uploadMsg}</p>
            )}
          </div>

          {/* Document list */}
          <div className="flex-1 overflow-auto px-4 pt-4 pb-4 space-y-2">
            <div className="flex items-center justify-between mb-1">
              <p className="text-[11px] font-semibold text-slate-500 dark:text-gray-400 uppercase tracking-wider">
                Indexed Documents ({status?.document_count ?? 0})
              </p>
              {status && status.total_chunks > 0 && (
                <span className="text-[10px] text-slate-400 dark:text-gray-500">
                  {status.total_chunks} chunks
                </span>
              )}
            </div>

            {!status?.documents?.length ? (
              <p className="text-xs text-slate-400 dark:text-gray-500 italic">No documents uploaded yet.</p>
            ) : (
              status.documents.map((doc) => (
                <div
                  key={doc.name}
                  className="flex items-center gap-2 bg-slate-100 dark:bg-gray-800 rounded-lg px-2 py-1.5 group border border-slate-200 dark:border-transparent"
                >
                  <span className="text-sm shrink-0">{extIcon(doc.extension)}</span>
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-slate-700 dark:text-gray-200 truncate font-medium" title={doc.name}>
                      {doc.name}
                    </p>
                    <p className="text-[10px] text-slate-400 dark:text-gray-500">{doc.size_kb} KB</p>
                  </div>
                  <button
                    onClick={() => handleDelete(doc.name)}
                    disabled={deletingFile === doc.name}
                    className="opacity-0 group-hover:opacity-100 text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 disabled:opacity-40 text-xs transition-opacity shrink-0 font-bold"
                    title="Remove document"
                  >
                    {deletingFile === doc.name ? "…" : "✕"}
                  </button>
                </div>
              ))
            )}
          </div>

          {/* Reset / clear actions */}
          <div className="px-4 pb-4 pt-2 border-t border-slate-100 dark:border-gray-800 space-y-2">
            <button
              onClick={handleClearChat}
              disabled={messages.length === 0}
              className="w-full bg-slate-100 hover:bg-slate-200 text-slate-700 dark:bg-gray-800 dark:hover:bg-gray-700 dark:text-gray-200 disabled:opacity-30 disabled:cursor-not-allowed text-xs font-medium rounded-lg px-3 py-2 transition-colors border border-slate-200 dark:border-transparent"
            >
              💬 Clear Chat History
            </button>
            <button
              onClick={handleReset}
              disabled={resetting || !backendOk}
              className="w-full bg-red-50 hover:bg-red-100 text-red-700 dark:bg-red-900/40 dark:hover:bg-red-900/60 dark:text-red-300 disabled:opacity-30 disabled:cursor-not-allowed text-xs font-medium rounded-lg px-3 py-2 transition-colors border border-red-100 dark:border-transparent"
            >
              {resetting ? "Resetting…" : "🧹 Reset Everything (wipe all docs + chat)"}
            </button>
          </div>
        </aside>

        {/* ── Main Chat ──────────────────────────────────────────────────────── */}
        <div className="flex flex-1 flex-col overflow-hidden">

          {/* Header */}
          <header className="border-b border-slate-200 dark:border-gray-800 px-6 py-3 bg-white/50 dark:bg-gray-900/40 shrink-0 flex items-center justify-between">
            <div>
              <h2 className="text-sm font-semibold text-slate-800 dark:text-gray-200">
                Ask about your documents
              </h2>
              <p className="text-xs text-slate-500 mt-0.5">
                Answers include exact page numbers and quoted text from the source document.
              </p>
            </div>
            <div className="text-right">
              <p className="text-[10px] text-slate-400 dark:text-gray-500 uppercase tracking-wider">Session</p>
              <p className="text-xs text-slate-600 dark:text-gray-300 font-mono">
                {messages.filter((m) => m.role === "user").length} questions · {messages.filter((m) => m.role === "assistant").length} answers
              </p>
            </div>
          </header>

          {/* Messages */}
          <div className="flex-1 overflow-y-auto px-6 py-5 space-y-6">

            {messages.length === 0 && (
              <div className="flex flex-col items-center justify-center h-full text-center gap-4 opacity-75">
                <span className="text-5xl">🏭</span>
                <div className="space-y-1">
                  <p className="text-slate-700 dark:text-gray-300 text-sm font-medium">
                    Upload a document, then ask any question.
                  </p>
                  <p className="text-slate-500 dark:text-gray-500 text-xs max-w-sm">
                    Works with company manuals, production SOPs, quality procedures,
                    safety sheets, HR policies, and more.
                  </p>
                  <div className="flex flex-wrap gap-2 justify-center mt-3">
                    {[
                      "What does error code E3 mean?",
                      "What is the maintenance schedule?",
                      "What are the safety requirements?",
                      "What temperature is required for process X?",
                    ].map((q) => (
                      <button
                        key={q}
                        onClick={() => setInput(q)}
                        className="text-xs bg-white dark:bg-gray-800 hover:bg-slate-100 dark:hover:bg-gray-700 text-slate-700 dark:text-gray-300 px-3 py-1.5 rounded-full transition-colors border border-slate-200 dark:border-transparent shadow-xs"
                      >
                        {q}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            )}

            {messages.map((m) => (
              <div key={m.ts} className={`flex ${m.role === "user" ? "justify-end" : "justify-start"}`}>
                <div className={`max-w-[80%] space-y-2 ${m.role === "user" ? "items-end" : "items-start"} flex flex-col`}>

                  {/* Bubble */}
                  <div
                    className={`rounded-2xl px-4 py-3 text-sm leading-relaxed ${m.role === "user"
                      ? "bg-blue-600 text-white rounded-br-sm shadow-sm"
                      : m.error
                        ? "bg-red-50 text-red-800 border border-red-200 rounded-bl-sm dark:bg-red-900/40 dark:text-red-300 dark:border-red-700/50"
                        : "bg-white text-slate-800 border border-slate-200 rounded-bl-sm shadow-xs dark:bg-gray-800 dark:text-gray-100 dark:border-transparent"
                      }`}
                  >
                    <p className="whitespace-pre-wrap">{m.content}</p>
                  </div>

                  {/* Sources (source highlighting) */}
                  {m.sources && m.sources.length > 0 && (
                    <div className="w-full space-y-1.5">
                      <p className="text-[11px] text-slate-400 dark:text-gray-500 px-1">
                        {m.chunks_searched} chunks searched · {m.sources.length} source
                        {m.sources.length !== 1 ? "s" : ""} matched
                      </p>
                      {m.sources.map((src, j) => (
                        <SourceCard key={`${m.ts}-${j}`} source={src} />
                      ))}
                    </div>
                  )}
                </div>
              </div>
            ))}

            {/* Loading indicator */}
            {loading && (
              <div className="flex justify-start">
                <div className="bg-white border border-slate-200 dark:bg-gray-800 dark:border-transparent rounded-2xl rounded-bl-sm px-4 py-3 shadow-xs">
                  <div className="flex gap-1.5 items-center">
                    <span className="w-2 h-2 bg-blue-500 dark:bg-blue-400 rounded-full animate-bounce [animation-delay:0ms]" />
                    <span className="w-2 h-2 bg-blue-500 dark:bg-blue-400 rounded-full animate-bounce [animation-delay:150ms]" />
                    <span className="w-2 h-2 bg-blue-500 dark:bg-blue-400 rounded-full animate-bounce [animation-delay:300ms]" />
                    <span className="text-xs text-slate-500 dark:text-gray-400 ml-2">
                      Hermes is searching the documents…
                    </span>
                  </div>
                </div>
              </div>
            )}

            <div ref={bottomRef} />
          </div>

          {/* Input */}
          <footer className="border-t border-slate-200 dark:border-gray-800 px-6 py-4 bg-white/50 dark:bg-gray-900/40 shrink-0">
            <div className="flex gap-3">
              <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && handleSend()}
                disabled={loading || !allOk}
                placeholder={
                  !backendOk
                    ? "Backend offline…"
                    : !ollamaOk
                    ? "Ollama offline — start the Ollama service…"
                    : !llmOk
                    ? `Run: ollama pull ${health?.llm_model_configured ?? "hermes3"}`
                    : !embedOk
                    ? `Run: ollama pull ${health?.embed_model_configured ?? "nomic-embed-text"}`
                    : !status?.index_ready
                    ? "Upload a document to start…"
                    : "Ask a specific question about your documents…"
                }
                className="flex-1 bg-white border border-slate-200 rounded-xl px-4 py-3 text-sm text-slate-800 placeholder-slate-400 focus:outline-none focus:border-blue-500 disabled:opacity-40 disabled:cursor-not-allowed transition-colors shadow-xs dark:bg-gray-800 dark:border-gray-700 dark:text-gray-100 dark:placeholder-gray-500 dark:focus:border-blue-500"
              />
              <button
                onClick={handleSend}
                disabled={loading || !input.trim() || !allOk || !status?.index_ready}
                className="bg-blue-600 hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed text-white font-medium text-sm rounded-xl px-5 py-3 transition-colors shrink-0"
              >
                Send
              </button>
            </div>
            <p className="text-[11px] text-slate-400 dark:text-gray-600 mt-2 text-center">
              All processing happens locally on your machine · No internet required · No data sent to cloud
            </p>
          </footer>
        </div>
      </div>
    </div>
  );
}

// ── Status Badge ──────────────────────────────────────────────────────────────

function StatusBadge({
  label,
  ok,
  loading,
  okText,
  failText,
}: {
  label: string;
  ok: boolean;
  loading?: boolean;
  okText: string;
  failText: string;
}) {
  return (
    <div
      className={`text-[11px] px-2.5 py-1.5 rounded-md font-medium flex items-center gap-2 ${loading
        ? "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300"
        : ok
          ? "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300"
          : "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300"
        }`}
      title={ok ? okText : failText}
    >
      <span className="font-semibold w-12 shrink-0">{label}</span>
      <span className="truncate">{loading ? "checking…" : ok ? okText : failText}</span>
    </div>
  );
}
