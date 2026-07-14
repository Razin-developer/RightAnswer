"use client";

import type { AnswerFormat, AnswerPayload } from "@right-answer/types";

import { useEffect, useState, useTransition } from "react";

import { askQuestion, fetchChapters, fetchSubjects } from "@/lib/api";

const answerFormats: { value: AnswerFormat; label: string }[] = [
  { value: "1_mark", label: "1 Mark" },
  { value: "3_mark", label: "3 Marks" },
  { value: "5_mark", label: "5 Marks" },
  { value: "simple_explanation", label: "Simple" },
  { value: "malayalam_explanation", label: "Malayalam" },
];

interface SubjectSummary {
  id: string;
  name: string;
  code: string;
}

interface ChapterSummary {
  id: string;
  chapterNumber: number;
  title: string;
}

export function AskForm({
  onAnswer,
}: {
  onAnswer: (answer: AnswerPayload | null) => void;
}) {
  const [subjects, setSubjects] = useState<SubjectSummary[]>([]);
  const [chapters, setChapters] = useState<ChapterSummary[]>([]);
  const [subjectId, setSubjectId] = useState<string>("");
  const [chapterId, setChapterId] = useState<string>("");
  const [question, setQuestion] = useState("");
  const [language, setLanguage] = useState<"en" | "ml">("en");
  const [answerType, setAnswerType] = useState<AnswerFormat>("3_mark");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    fetchSubjects().then(setSubjects).catch(() => setSubjects([]));
  }, []);

  useEffect(() => {
    if (!subjectId) {
      setChapters([]);
      setChapterId("");
      return;
    }

    fetchChapters(subjectId)
      .then((nextChapters) => setChapters(nextChapters))
      .catch(() => setChapters([]));
  }, [subjectId]);

  return (
    <form
      className="grid gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        startTransition(async () => {
          try {
            setError(null);
            const answer = await askQuestion({
              question,
              language,
              subjectId: subjectId || null,
              chapterId: chapterId || null,
              answerType,
            });
            onAnswer(answer);
          } catch (nextError) {
            setError(nextError instanceof Error ? nextError.message : "Could not fetch an answer.");
            onAnswer(null);
          }
        });
      }}
    >
      <div className="grid gap-4 md:grid-cols-2">
        <select
          className="rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm outline-none"
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
          className="rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm outline-none"
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

      <textarea
        className="min-h-36 rounded-3xl border border-slate-200 bg-white px-4 py-4 text-base outline-none"
        placeholder="Ask a Kerala SSLC textbook question"
        value={question}
        onChange={(event) => setQuestion(event.target.value)}
      />

      <div className="flex flex-wrap items-center gap-3">
        {answerFormats.map((format) => (
          <button
            key={format.value}
            type="button"
            className={`rounded-full px-4 py-2 text-sm ${
              answerType === format.value
                ? "bg-ink text-white"
                : "border border-slate-200 bg-white text-slate-600"
            }`}
            onClick={() => setAnswerType(format.value)}
          >
            {format.label}
          </button>
        ))}

        <div className="ml-auto flex rounded-full border border-slate-200 bg-white p-1">
          <button
            type="button"
            className={`rounded-full px-4 py-2 text-sm ${language === "en" ? "bg-sea text-white" : "text-slate-600"}`}
            onClick={() => setLanguage("en")}
          >
            English
          </button>
          <button
            type="button"
            className={`rounded-full px-4 py-2 text-sm ${language === "ml" ? "bg-sea text-white" : "text-slate-600"}`}
            onClick={() => setLanguage("ml")}
          >
            Malayalam
          </button>
        </div>
      </div>

      <button
        type="submit"
        disabled={isPending || !question.trim()}
        className="rounded-full bg-coral px-5 py-3 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending ? "Finding the right answer..." : "Ask Right Answer"}
      </button>

      {error ? <p className="text-sm text-red-600">{error}</p> : null}
    </form>
  );
}
