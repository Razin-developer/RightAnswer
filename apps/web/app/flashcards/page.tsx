import { PageShell } from "@/components/page-shell";
import { SimpleListCard } from "@/components/simple-list-card";

export default function FlashcardsPage() {
  return (
    <PageShell>
      <SimpleListCard
        eyebrow="Flashcards"
        title="Quick memory cards"
        description="Flashcards will later be sourced from pre-generated and verified chapter artifacts."
        items={[
          "Q: What is photosynthesis? A: Process by which green plants prepare food.",
          "Q: Which pigment traps sunlight? A: Chlorophyll.",
          "Q: Name one output of photosynthesis. A: Oxygen.",
        ]}
      />
    </PageShell>
  );
}
