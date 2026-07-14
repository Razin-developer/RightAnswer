import { PageShell } from "@/components/page-shell";
import { SimpleListCard } from "@/components/simple-list-card";

export default function QuizPage() {
  return (
    <PageShell>
      <SimpleListCard
        eyebrow="Quiz"
        title="Self-test mode"
        description="Quiz generation is connected to textbook-grounded prompts and can be deepened with teacher review."
        items={[
          "1. What is the basic definition of photosynthesis?",
          "2. Why is chlorophyll important?",
          "3. Write one textbook-grounded point about oxygen release.",
        ]}
      />
    </PageShell>
  );
}
