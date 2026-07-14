import type { AnswerPayload, AskQuestionInput } from "@right-answer/types";

import { getAuthToken } from "./auth";

const apiBaseUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000/api/v1";

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(getAuthToken() ? { Authorization: `Bearer ${getAuthToken()}` } : {}),
      ...(init?.headers ?? {}),
    },
    cache: "no-store",
  });

  if (!response.ok) {
    const error = await response.json().catch(() => null);
    throw new Error(error?.error?.message ?? `Request failed: ${response.status}`);
  }

  const payload = (await response.json()) as { data: T };
  return payload.data;
}

export interface SubjectSummary {
  id: string;
  name: string;
  code: string;
}

export interface ChapterSummary {
  id: string;
  chapterNumber: number;
  title: string;
}

export function fetchSubjects() {
  return request<SubjectSummary[]>("/subjects");
}

export function fetchChapters(subjectId: string) {
  return request<ChapterSummary[]>(`/subjects/${subjectId}/chapters`);
}

export function askQuestion(payload: AskQuestionInput) {
  return request<AnswerPayload>("/ask", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function signup(payload: {
  fullName: string;
  email: string;
  password: string;
  role?: "student" | "teacher";
}) {
  return request<{ token: string; user: { email: string; role: string } }>("/auth/signup", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function login(payload: { email: string; password: string }) {
  return request<{ token: string; user: { email: string; role: string } }>("/auth/login", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function fetchMe() {
  return request<{
    id: string;
    email: string;
    role: string;
    planCode: string;
    profile?: { fullName?: string | null };
  }>("/users/me");
}

export function fetchUsage() {
  return request<{
    planCode: string;
    limits: {
      cachedDailyLimit: number;
      liveDailyLimit: number;
      premiumDailyLimit: number;
    };
    usage: Array<{ eventType: string; _count: { eventType: number } }>;
  }>("/usage/me");
}

export function fetchHistory() {
  return request<
    Array<{
      requestId: string;
      question: string;
      confidence: number;
      createdAt: string;
    }>
  >("/users/me/history");
}

export function fetchRevision(chapterId: string) {
  return request<{
    chapter: { id: string; chapterNumber: number; title: string };
    keyPoints: string[];
  }>(`/chapters/${chapterId}/revision`);
}

export function fetchSubscription() {
  return request<{
    planCode: string;
    subscription: { status: string; startsAt: string } | null;
  }>("/subscriptions/me");
}

export function fetchFeedbackList() {
  return request<Array<{ id: string; rating: number; feedbackText?: string | null }>>("/feedback");
}

export function fetchExamMode() {
  return request<{ enabled: boolean; freePremiumDisabled: boolean }>("/admin/exam-mode");
}

export function fetchCommonDoubts() {
  return request<Array<{ question: string; count: number }>>("/teacher/common-doubts");
}
