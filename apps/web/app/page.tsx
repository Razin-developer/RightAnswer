"use client";

import Link from "next/link";

import { PageShell } from "@/components/page-shell";
import { SectionCard } from "@/components/section-card";

export default function HomePage() {
  return (
    <PageShell>
      <SectionCard className="overflow-hidden bg-gradient-to-br from-white to-amber-50">
        <div className="grid gap-8 lg:grid-cols-[1.2fr_0.8fr]">
          <div className="space-y-6">
            <span className="inline-flex rounded-full bg-saffron/15 px-4 py-2 text-xs font-semibold uppercase tracking-[0.3em] text-saffron">
              Kerala SSLC Study Companion
            </span>
            <div className="space-y-4">
              <h1 className="max-w-3xl text-4xl font-semibold tracking-tight text-ink md:text-6xl">
                Textbook-grounded answers built for Kerala Class 10 exams.
              </h1>
              <p className="max-w-2xl text-base leading-7 text-slate-600 md:text-lg">
                Right Answer is not a generic chatbot. It is a Kerala SSLC-first study app that
                answers chapter questions, explains diagrams, and gives exam-ready 1, 3, and 5 mark
                answers with chapter and page citations.
              </p>
            </div>
            <div className="flex flex-wrap gap-3">
              <Link
                href="/dashboard"
                className="rounded-full bg-coral px-5 py-3 text-sm font-semibold text-white"
              >
                Open student dashboard
              </Link>
              <Link
                href="/login"
                className="rounded-full border border-slate-200 bg-white px-5 py-3 text-sm font-semibold text-slate-700"
              >
                Login with demo account
              </Link>
            </div>
          </div>

          <div className="grid gap-4">
            <SectionCard className="bg-ink text-white">
              <p className="text-xs uppercase tracking-[0.3em] text-white/60">Why it feels different</p>
              <ul className="mt-4 space-y-3 text-sm text-white/85">
                <li>Textbook-first retrieval instead of open-ended AI chat</li>
                <li>Exam-mode buttons for fast 1 mark, 3 mark, and 5 mark answers</li>
                <li>Malayalam and English support with chapter/page citations</li>
              </ul>
            </SectionCard>
            <SectionCard>
              <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Exam mode ready</p>
              <p className="mt-3 text-sm leading-6 text-slate-600">
                Hot-cache answers, quick revision flows, and strict premium-fallback protection for
                peak traffic.
              </p>
            </SectionCard>
          </div>
        </div>
      </SectionCard>

      <div className="grid gap-4 md:grid-cols-3">
        <SectionCard>
          <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Student flow</p>
          <h2 className="mt-2 text-2xl font-semibold text-ink">Ask, revise, repeat</h2>
          <p className="mt-2 text-sm text-slate-600">
            The dashboard is tuned for subject choice, chapter choice, and answer format first.
          </p>
        </SectionCard>
        <SectionCard>
          <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Teacher flow</p>
          <h2 className="mt-2 text-2xl font-semibold text-ink">Verify and generate</h2>
          <p className="mt-2 text-sm text-slate-600">
            Teacher tools promote good answers into the Gold cache and generate worksheets.
          </p>
        </SectionCard>
        <SectionCard>
          <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Admin flow</p>
          <h2 className="mt-2 text-2xl font-semibold text-ink">Ingest and govern</h2>
          <p className="mt-2 text-sm text-slate-600">
            Admin tools manage textbook versions, ingestion jobs, model providers, and exam mode.
          </p>
        </SectionCard>
      </div>
    </PageShell>
  );
}
