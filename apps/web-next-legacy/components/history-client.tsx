"use client";

import { useEffect, useState } from "react";

import { fetchHistory } from "@/lib/api";

import { SectionCard } from "./section-card";

export function HistoryClient() {
  const [history, setHistory] = useState<
    Array<{ requestId: string; question: string; confidence: number; createdAt: string }>
  >([]);

  useEffect(() => {
    fetchHistory().then(setHistory).catch(() => setHistory([]));
  }, []);

  return (
    <SectionCard className="space-y-4">
      <div>
        <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Answer history</p>
        <h1 className="mt-2 text-3xl font-semibold text-ink">Recent study questions</h1>
      </div>
      <div className="grid gap-3">
        {history.map((item) => (
          <div key={item.requestId} className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
            <p className="font-medium text-ink">{item.question}</p>
            <p className="mt-1 text-sm text-slate-600">
              Confidence {Math.round(item.confidence * 100)}% • {new Date(item.createdAt).toLocaleString()}
            </p>
          </div>
        ))}
        {!history.length ? <p className="text-sm text-slate-500">No history yet.</p> : null}
      </div>
    </SectionCard>
  );
}
