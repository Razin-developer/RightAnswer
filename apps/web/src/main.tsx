import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Activity,
  BarChart3,
  BookOpen,
  Brain,
  ChevronRight,
  Database,
  FileText,
  Gauge,
  Library,
  Menu,
  Server,
  Shield,
  Sparkles,
  Users
} from "lucide-react";

import "./styles/app.css";

const apiUrl = import.meta.env.VITE_API_URL ?? "http://localhost:4000/api";

type Page = "home" | "features" | "docs" | "admin";

type Metrics = {
  aiUsage: Array<{
    model: string;
    provider: string;
    apiCalls: number;
    inputTokens: number;
    outputTokens: number;
    estimatedCostUsd: number;
  }>;
  userUsage: Array<{
    userId: string | null;
    email: string | null;
    apiCalls: number;
    inputTokens: number;
    outputTokens: number;
    estimatedCostUsd: number;
  }>;
  notes: string[];
};

function App() {
  const [page, setPage] = useState<Page>(() => {
    const hash = window.location.hash.replace("#", "");
    return ["features", "docs", "admin"].includes(hash) ? (hash as Page) : "home";
  });

  useEffect(() => {
    window.location.hash = page === "home" ? "" : page;
  }, [page]);

  return (
    <main>
      <TopNav page={page} onPage={setPage} />
      {page === "home" && <Landing onPage={setPage} />}
      {page === "features" && <Features />}
      {page === "docs" && <Docs />}
      {page === "admin" && <Admin />}
    </main>
  );
}

function TopNav({ page, onPage }: { page: Page; onPage: (page: Page) => void }) {
  const [open, setOpen] = useState(false);
  const items: Array<[Page, string]> = [
    ["home", "Home"],
    ["features", "App Features"],
    ["docs", "Documentation"],
    ["admin", "Admin"]
  ];
  return (
    <header className="topbar">
      <button className="brand" onClick={() => onPage("home")}>
        <Sparkles size={20} />
        RightAnswer
      </button>
      <button className="menu" onClick={() => setOpen((value) => !value)}>
        <Menu size={20} />
      </button>
      <nav className={open ? "nav open" : "nav"}>
        {items.map(([id, label]) => (
          <button
            key={id}
            className={page === id ? "active" : ""}
            onClick={() => {
              onPage(id);
              setOpen(false);
            }}
          >
            {label}
          </button>
        ))}
      </nav>
    </header>
  );
}

function Landing({ onPage }: { onPage: (page: Page) => void }) {
  return (
    <>
      <section className="hero">
        <div>
          <p className="eyebrow">Local-first AI study partner</p>
          <h1>RightAnswer</h1>
          <p className="lead">
            A textbook-grounded learning system with Rust APIs, Qdrant retrieval,
            OpenRouter models, rich diagrams, LaTeX, tables, charts, and offline
            SQLite reading in the Flutter app.
          </p>
          <div className="actions">
            <button className="primary" onClick={() => onPage("features")}>
              Explore features <ChevronRight size={18} />
            </button>
            <button className="secondary" onClick={() => onPage("docs")}>
              Read docs
            </button>
          </div>
        </div>
        <div className="system-panel">
          <Metric icon={<Server />} label="Backend" value="Rust + Axum" />
          <Metric icon={<Database />} label="Storage" value="Postgres + Qdrant" />
          <Metric icon={<Brain />} label="AI" value="OpenRouter / HackAI" />
          <Metric icon={<Gauge />} label="App" value="Flutter + SQLite" />
        </div>
      </section>
      <section className="band">
        <FeatureGrid />
      </section>
    </>
  );
}

function Features() {
  return (
    <section className="page">
      <p className="eyebrow">Main app features</p>
      <h2>Built for school answers that need more than text</h2>
      <FeatureGrid />
      <div className="split">
        <ArticleCard title="Rich answers">
          Markdown, LaTeX, tables, charts, geometry diagrams, source images, and
          clean speaker-only transcripts are generated as one structured response.
        </ArticleCard>
        <ArticleCard title="Local-first mode">
          The Flutter app stores subjects, chapters, chats, plans, and exams in
          SQLite. Offline mode reads local data and pauses AI generation.
        </ArticleCard>
      </div>
    </section>
  );
}

function Docs() {
  return (
    <section className="page docs">
      <p className="eyebrow">Documentation</p>
      <h2>System contract</h2>
      <ArticleCard title="RAG pipeline">
        Query text is embedded, Qdrant returns candidate textbook chunks, the
        rerank model selects the best 3 to 5 contexts, and the chat model gets
        only those selected contexts plus the rich-answer prompt contract.
      </ArticleCard>
      <ArticleCard title="Answer format">
        The backend asks for JSON schema <code>right_answer.rich_answer.v1</code>
        with <code>renderMarkdown</code>, <code>speechText</code>, typed{" "}
        <code>blocks</code>, <code>sources</code>, limitations, and confidence.
      </ArticleCard>
      <ArticleCard title="Data safety">
        PostgreSQL is the source of relational truth. Qdrant stores vectors and
        payload copies for retrieval. Migration scripts must verify row counts
        and stop before destructive writes if counts mismatch.
      </ArticleCard>
      <ArticleCard title="Deployment">
        The VPS stack runs Rust API, React static site, PostgreSQL, Qdrant, and
        optional Redis/workers. Node and Next are kept in legacy folders until all
        parity checks pass.
      </ArticleCard>
    </section>
  );
}

function Admin() {
  const [token, setToken] = useState(() => localStorage.getItem("ra_admin_token") ?? "");
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function load() {
    setLoading(true);
    setError("");
    localStorage.setItem("ra_admin_token", token);
    try {
      const response = await fetch(`${apiUrl}/admin/metrics`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {}
      });
      if (!response.ok) {
        throw new Error(`Admin metrics failed: ${response.status}`);
      }
      const payload = (await response.json()) as { data: Metrics };
      setMetrics(payload.data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load metrics");
    } finally {
      setLoading(false);
    }
  }

  const totals = useMemo(() => {
    const rows = metrics?.aiUsage ?? [];
    return rows.reduce(
      (acc, row) => ({
        calls: acc.calls + row.apiCalls,
        tokens: acc.tokens + row.inputTokens + row.outputTokens,
        cost: acc.cost + row.estimatedCostUsd
      }),
      { calls: 0, tokens: 0, cost: 0 }
    );
  }, [metrics]);

  return (
    <section className="page">
      <p className="eyebrow">Admin</p>
      <h2>AI usage, users, and estimated expense</h2>
      <div className="admin-controls">
        <input
          type="password"
          placeholder="Admin JWT"
          value={token}
          onChange={(event) => setToken(event.target.value)}
        />
        <button className="primary" onClick={load}>
          {loading ? "Loading..." : "Load metrics"}
        </button>
      </div>
      {error && <p className="error">{error}</p>}
      {metrics && (
        <>
          <div className="metrics">
            <Metric icon={<Activity />} label="API calls" value={String(totals.calls)} />
            <Metric icon={<BarChart3 />} label="Tokens" value={totals.tokens.toLocaleString()} />
            <Metric icon={<Shield />} label="Est. cost" value={`$${totals.cost.toFixed(4)}`} />
          </div>
          <DataTable
            title="Usage by model"
            rows={metrics.aiUsage}
            columns={["provider", "model", "apiCalls", "inputTokens", "outputTokens", "estimatedCostUsd"]}
          />
          <DataTable
            title="Usage by user"
            rows={metrics.userUsage}
            columns={["email", "userId", "apiCalls", "inputTokens", "outputTokens", "estimatedCostUsd"]}
          />
        </>
      )}
    </section>
  );
}

function FeatureGrid() {
  const features = [
    [<Library />, "Textbook grounded", "Answers are built from local textbook content and selected source chunks."],
    [<FileText />, "Rich rendering", "LaTeX, tables, charts, diagrams, SVG, code, images, and clean TTS output."],
    [<Database />, "SQLite offline", "The mobile app opens past chats and local textbook data without network checks."],
    [<Users />, "Sync and sharing", "Authenticated users can sync chats and share supported outputs when online."]
  ] as const;
  return (
    <div className="grid">
      {features.map(([icon, title, text]) => (
        <div className="feature" key={title}>
          {icon}
          <h3>{title}</h3>
          <p>{text}</p>
        </div>
      ))}
    </div>
  );
}

function ArticleCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <article className="article">
      <h3>{title}</h3>
      <p>{children}</p>
    </article>
  );
}

function Metric({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="metric">
      {icon}
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function DataTable<T extends Record<string, unknown>>({
  title,
  rows,
  columns
}: {
  title: string;
  rows: T[];
  columns: Array<keyof T & string>;
}) {
  return (
    <div className="table-wrap">
      <h3>{title}</h3>
      <table>
        <thead>
          <tr>
            {columns.map((column) => (
              <th key={column}>{column}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={index}>
              {columns.map((column) => (
                <td key={column}>{formatCell(row[column])}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function formatCell(value: unknown) {
  if (typeof value === "number") {
    return value.toLocaleString(undefined, { maximumFractionDigits: 6 });
  }
  return value == null || value === "" ? "anonymous" : String(value);
}

createRoot(document.getElementById("root")!).render(<App />);
