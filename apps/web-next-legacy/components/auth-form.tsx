"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { login, signup } from "@/lib/api";
import { setAuthToken } from "@/lib/auth";

import { SectionCard } from "./section-card";

export function AuthForm({ mode }: { mode: "login" | "signup" }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  return (
    <SectionCard className="mx-auto w-full max-w-xl">
      <form
        className="grid gap-4"
        onSubmit={(event) => {
          event.preventDefault();
          const formData = new FormData(event.currentTarget);
          startTransition(async () => {
            setError(null);
            try {
              const payload =
                mode === "login"
                  ? await login({
                      email: String(formData.get("email")),
                      password: String(formData.get("password")),
                    })
                  : await signup({
                      fullName: String(formData.get("fullName")),
                      email: String(formData.get("email")),
                      password: String(formData.get("password")),
                    });
              setAuthToken(payload.token);
              router.push("/dashboard");
            } catch (nextError) {
              setError(nextError instanceof Error ? nextError.message : "Authentication failed.");
            }
          });
        }}
      >
        <div className="space-y-2">
          <p className="text-xs uppercase tracking-[0.3em] text-slate-500">
            {mode === "login" ? "Login" : "Sign up"}
          </p>
          <h1 className="text-3xl font-semibold text-ink">
            {mode === "login" ? "Continue your SSLC study flow" : "Create a student account"}
          </h1>
          <p className="text-sm text-slate-600">
            Demo credentials after seeding: `student@rightanswer.local` / `Password123!`
          </p>
        </div>

        {mode === "signup" ? (
          <input
            name="fullName"
            placeholder="Full name"
            className="rounded-2xl border border-slate-200 px-4 py-3"
            required
          />
        ) : null}

        <input
          name="email"
          type="email"
          placeholder="Email address"
          className="rounded-2xl border border-slate-200 px-4 py-3"
          required
        />
        <input
          name="password"
          type="password"
          placeholder="Password"
          className="rounded-2xl border border-slate-200 px-4 py-3"
          required
        />

        {error ? <p className="text-sm text-red-600">{error}</p> : null}

        <button
          type="submit"
          disabled={isPending}
          className="rounded-full bg-ink px-5 py-3 text-sm font-semibold text-white"
        >
          {isPending ? "Please wait..." : mode === "login" ? "Login" : "Create account"}
        </button>
      </form>
    </SectionCard>
  );
}
