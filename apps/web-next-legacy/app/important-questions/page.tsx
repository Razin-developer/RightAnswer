import { PageShell } from "@/components/page-shell";
import { SimpleListCard } from "@/components/simple-list-card";

export default function ImportantQuestionsPage() {
  return (
    <PageShell>
      <SimpleListCard
        eyebrow="Important Questions"
        title="High-priority revision prompts"
        description="This page is ready for chapter-driven important question generation from cached or retrieved textbook content."
        items={[
          "Define photosynthesis in one sentence.",
          "Explain the role of chlorophyll in 3 marks.",
          "Write a 5-mark answer on the steps of food preparation in plants.",
        ]}
      />
    </PageShell>
  );
}
