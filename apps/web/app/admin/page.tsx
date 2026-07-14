"use client";

import { useEffect, useState } from "react";

import { fetchExamMode, fetchFeedbackList } from "@/lib/api";
import { PageShell } from "@/components/page-shell";
import { SectionCard } from "@/components/section-card";

export default function AdminPage() {
  const [examMode, setExamMode] = useState<{ enabled: boolean; freePremiumDisabled: boolean } | null>(null);
  const [feedback, setFeedback] = useState<Array<{ id: string; rating: number; feedbackText?: string | null }>>([]);

  useEffect(() => {
    fetchExamMode().then(setExamMode).catch(() => setExamMode(null));
    fetchFeedbackList().then(setFeedback).catch(() => setFeedback([]));
  }, []);

  return (
    <PageShell>
      <div className="grid gap-4 lg:grid-cols-[0.9fr_1.1fr]">
        <SectionCard className="space-y-4">
          <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Admin Dashboard</p>
          <h1 className="text-3xl font-semibold text-ink">Govern ingestion, providers, and exam mode</h1>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
            <p className="font-medium text-ink">Exam mode: {examMode?.enabled ? "Enabled" : "Disabled"}</p>
            <p className="text-sm text-slate-600">
              Free-user premium fallback: {examMode?.freePremiumDisabled ? "Blocked" : "Allowed"}
            </p>
          </div>
        </SectionCard>
        <SectionCard className="space-y-4">
          <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Recent feedback</p>
          <div className="grid gap-3">
            {feedback.map((item) => (
              <div key={item.id} className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
                <p className="font-medium text-ink">Rating: {item.rating}/5</p>
                <p className="text-sm text-slate-600">{item.feedbackText ?? "No written comment."}</p>
              </div>
            ))}
            {!feedback.length ? <p className="text-sm text-slate-500">Admin login required to view moderation data.</p> : null}
          </div>
        </SectionCard>
      </div>
    </PageShell>
  );
}
