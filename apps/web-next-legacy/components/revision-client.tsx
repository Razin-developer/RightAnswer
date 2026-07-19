"use client";

import { useEffect, useState } from "react";

import { fetchChapters, fetchRevision, fetchSubjects } from "@/lib/api";

import { SectionCard } from "./section-card";

export function RevisionClient() {
  const [subjectId, setSubjectId] = useState("");
  const [chapterId, setChapterId] = useState("");
  const [subjects, setSubjects] = useState<Array<{ id: string; name: string }>>([]);
  const [chapters, setChapters] = useState<Array<{ id: string; chapterNumber: number; title: string }>>([]);
  const [bundle, setBundle] = useState<{ chapter: { title: string }; keyPoints: string[] } | null>(null);

  useEffect(() => {
    fetchSubjects().then(setSubjects).catch(() => setSubjects([]));
  }, []);

  useEffect(() => {
    if (!subjectId) return;
    fetchChapters(subjectId).then(setChapters).catch(() => setChapters([]));
  }, [subjectId]);

  useEffect(() => {
    if (!chapterId) return;
    fetchRevision(chapterId).then(setBundle).catch(() => setBundle(null));
  }, [chapterId]);

  return (
    <SectionCard className="space-y-5">
      <div>
        <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Revision</p>
        <h1 className="mt-2 text-3xl font-semibold text-ink">Chapter-wise key points</h1>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <select
          className="rounded-2xl border border-slate-200 bg-white px-4 py-3"
          value={subjectId}
          onChange={(event) => setSubjectId(event.target.value)}
        >
          <option value="">Select subject</option>
          {subjects.map((subject) => (
            <option key={subject.id} value={subject.id}>
              {subject.name}
            </option>
          ))}
        </select>
        <select
          className="rounded-2xl border border-slate-200 bg-white px-4 py-3"
          value={chapterId}
          onChange={(event) => setChapterId(event.target.value)}
        >
          <option value="">Select chapter</option>
          {chapters.map((chapter) => (
            <option key={chapter.id} value={chapter.id}>
              Chapter {chapter.chapterNumber}: {chapter.title}
            </option>
          ))}
        </select>
      </div>

      {bundle ? (
        <div className="grid gap-3">
          <h2 className="text-2xl font-semibold text-ink">{bundle.chapter.title}</h2>
          {bundle.keyPoints.map((point, index) => (
            <div key={`${index}-${point}`} className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
              {point}
            </div>
          ))}
        </div>
      ) : (
        <p className="text-sm text-slate-500">Choose a chapter to load revision points.</p>
      )}
    </SectionCard>
  );
}
