import { AuthForm } from "@/components/auth-form";
import { PageShell } from "@/components/page-shell";

export default function LoginPage() {
  return (
    <PageShell>
      <AuthForm mode="login" />
    </PageShell>
  );
}
