import type { PropsWithChildren } from "react";

import clsx from "clsx";

export function SectionCard({
  children,
  className,
}: PropsWithChildren<{ className?: string }>) {
  return (
    <section
      className={clsx(
        "rounded-3xl border border-white/70 bg-white/80 p-6 shadow-[0_20px_80px_-40px_rgba(15,23,42,0.35)] backdrop-blur",
        className,
      )}
    >
      {children}
    </section>
  );
}
