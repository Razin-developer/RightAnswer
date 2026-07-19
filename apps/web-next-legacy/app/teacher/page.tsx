"use client";

import { useEffect, useState } from "react";

import { fetchCommonDoubts } from "@/lib/api";
import { PageShell } from "@/components/page-shell";
import { SectionCard } from "@/components/section-card";

export default function TeacherPage() {
  const [doubts, setDoubts] = useState<Array<{ question: string; count: number }>>([]);

  useEffect(() => {
    fetchCommonDoubts().then(setDoubts).catch(() => setDoubts([]));
  }, []);

  return (
    <PageShell>
      <SectionCard className="space-y-4">
        <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Teacher Dashboard</p>
        <h1 className="text-3xl font-semibold text-ink">Worksheet and verification lane</h1>
        <p className="text-sm text-slate-600">
          This area is prepared for answer verification, worksheet generation, and common-doubt review.
        </p>
        <div className="grid gap-3">
          {doubts.map((doubt) => (
            <div key={doubt.question} className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="font-medium text-ink">{doubt.question}</p>
              <p className="text-sm text-slate-600">Seen {doubt.count} times</p>
            </div>
          ))}
          {!doubts.length ? <p className="text-sm text-slate-500">Teacher login required to load common doubts.</p> : null}
        </div>
      </SectionCard>
    </PageShell>
  );
}
