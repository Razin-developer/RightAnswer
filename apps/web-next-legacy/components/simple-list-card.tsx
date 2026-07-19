import type { PropsWithChildren } from "react";

import { SectionCard } from "./section-card";

export function SimpleListCard({
  eyebrow,
  title,
  description,
  items,
}: PropsWithChildren<{
  eyebrow: string;
  title: string;
  description: string;
  items: string[];
}>) {
  return (
    <SectionCard className="space-y-4">
      <div>
        <p className="text-xs uppercase tracking-[0.3em] text-slate-500">{eyebrow}</p>
        <h1 className="mt-2 text-3xl font-semibold text-ink">{title}</h1>
        <p className="mt-2 text-sm text-slate-600">{description}</p>
      </div>
      <div className="grid gap-3">
        {items.map((item) => (
          <div key={item} className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
            {item}
          </div>
        ))}
      </div>
    </SectionCard>
  );
}
