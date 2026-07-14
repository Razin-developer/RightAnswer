"use client";

import { useEffect, useState } from "react";

import type { AnswerPayload } from "@right-answer/types";

import { askQuestion, fetchMe, fetchSubjects, fetchUsage } from "@/lib/api";
import { getAuthToken } from "@/lib/auth";

import { AnswerCard } from "./answer-card";
import { AskForm } from "./ask-form";
import { SectionCard } from "./section-card";

export function DashboardClient() {
  const [answer, setAnswer] = useState<AnswerPayload | null>(null);
  const [profile, setProfile] = useState<{ email: string; role: string; planCode: string } | null>(null);
  const [usage, setUsage] = useState<{
    planCode: string;
    limits: { cachedDailyLimit: number; liveDailyLimit: number; premiumDailyLimit: number };
  } | null>(null);
  const [subjectCount, setSubjectCount] = useState(0);
  const [authError, setAuthError] = useState<string | null>(null);

  useEffect(() => {
    if (!getAuthToken()) {
      setAuthError("Login is required to ask textbook questions.");
      return;
    }

    fetchMe()
      .then((response) => setProfile(response))
      .catch((error) => setAuthError(error.message));
    fetchUsage().then(setUsage).catch(() => null);
    fetchSubjects().then((subjects) => setSubjectCount(subjects.length)).catch(() => null);
  }, []);

  return (
    <div className="grid gap-8">
      <div className="grid gap-4 lg:grid-cols-3">
        <SectionCard className="bg-ink text-white">
          <p className="text-xs uppercase tracking-[0.3em] text-white/60">Student dashboard</p>
          <h1 className="mt-3 text-3xl font-semibold">
            {profile?.role === "teacher" ? "Teacher session" : "Textbook-grounded study mode"}
          </h1>
          <p className="mt-4 text-sm text-white/80">
            {profile?.email ?? "Sign in to unlock cached answers, plan limits, and history."}
          </p>
        </SectionCard>
        <SectionCard>
          <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Plan</p>
          <h2 className="mt-3 text-2xl font-semibold text-ink">{usage?.planCode ?? "Unknown"}</h2>
          <p className="mt-2 text-sm text-slate-600">
            Cached answers: {usage?.limits.cachedDailyLimit ?? 0} • Live answers:{" "}
            {usage?.limits.liveDailyLimit ?? 0}
          </p>
        </SectionCard>
        <SectionCard>
          <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Corpus</p>
          <h2 className="mt-3 text-2xl font-semibold text-ink">{subjectCount} active subjects</h2>
          <p className="mt-2 text-sm text-slate-600">
            Kerala SSLC Class 10 with textbook-first routing and cache-first answer flow.
          </p>
        </SectionCard>
      </div>

      {authError ? <SectionCard><p className="text-sm text-red-600">{authError}</p></SectionCard> : null}

      <div className="grid gap-8 lg:grid-cols-[1fr_1fr]">
        <SectionCard className="space-y-5">
          <div className="space-y-2">
            <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Ask</p>
            <h2 className="text-2xl font-semibold text-ink">Choose your chapter and answer format</h2>
          </div>
          <AskForm onAnswer={setAnswer} />
        </SectionCard>
        <AnswerCard answer={answer} />
      </div>
    </div>
  );
}
