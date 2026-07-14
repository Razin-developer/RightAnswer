import type { PropsWithChildren } from "react";

import { TopNav } from "./top-nav";

export function PageShell({ children }: PropsWithChildren) {
  return (
    <div className="mx-auto flex min-h-screen w-full max-w-7xl flex-col gap-8 px-4 py-4 md:px-6">
      <TopNav />
      {children}
    </div>
  );
}
