"use client";

import type { AnswerPayload } from "@right-answer/types";

import { SectionCard } from "./section-card";

export function AnswerCard({ answer }: { answer: AnswerPayload | null }) {
  if (!answer) {
    return (
      <SectionCard className="min-h-64">
        <p className="text-sm text-slate-500">
          Ask a question to see a textbook-grounded answer with chapter and page citations.
        </p>
      </SectionCard>
    );
  }

  return (
    <SectionCard className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Answer</p>
          <h2 className="text-2xl font-semibold text-ink">{answer.answerType.replaceAll("_", " ")}</h2>
        </div>
        <span className="rounded-full bg-sea/10 px-3 py-1 text-xs font-medium text-sea">
          {answer.servedFrom}
        </span>
      </div>

      <p className="whitespace-pre-wrap text-base leading-7 text-slate-700">{answer.answerText}</p>

      <div className="space-y-2">
        <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Citations</p>
        <div className="flex flex-wrap gap-2">
          {answer.citations.map((citation) => (
            <span
              key={`${citation.contentUnitId}-${citation.pageNumber}`}
              className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1 text-xs text-slate-700"
            >
              {citation.chapterTitle} • Page {citation.pageNumber}
            </span>
          ))}
        </div>
      </div>
    </SectionCard>
  );
}
