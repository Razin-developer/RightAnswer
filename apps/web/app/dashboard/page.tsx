import { DashboardClient } from "@/components/dashboard-client";
import { PageShell } from "@/components/page-shell";

export default function DashboardPage() {
  return (
    <PageShell>
      <DashboardClient />
    </PageShell>
  );
}
