import { AuthForm } from "@/components/auth-form";
import { PageShell } from "@/components/page-shell";

export default function SignupPage() {
  return (
    <PageShell>
      <AuthForm mode="signup" />
    </PageShell>
  );
}
