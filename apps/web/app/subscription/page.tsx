"use client";

import { useEffect, useState } from "react";

import { fetchSubscription } from "@/lib/api";
import { PageShell } from "@/components/page-shell";
import { SectionCard } from "@/components/section-card";

export default function SubscriptionPage() {
  const [subscription, setSubscription] = useState<{
    planCode: string;
    subscription: { status: string; startsAt: string } | null;
  } | null>(null);

  useEffect(() => {
    fetchSubscription().then(setSubscription).catch(() => setSubscription(null));
  }, []);

  return (
    <PageShell>
      <SectionCard className="space-y-4">
        <p className="text-xs uppercase tracking-[0.3em] text-slate-500">Subscription</p>
        <h1 className="text-3xl font-semibold text-ink">Your plan and usage lane</h1>
        <p className="text-sm text-slate-600">
          Cached answers stay generous. Live AI and premium fallback remain protected by plan rules.
        </p>
        <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
          <p className="font-medium text-ink">Current plan: {subscription?.planCode ?? "Login required"}</p>
          <p className="mt-1 text-sm text-slate-600">
            Status: {subscription?.subscription?.status ?? "Unknown"} • Started:{" "}
            {subscription?.subscription?.startsAt
              ? new Date(subscription.subscription.startsAt).toLocaleDateString()
              : "N/A"}
          </p>
        </div>
      </SectionCard>
    </PageShell>
  );
}
