import { PageShell } from "@/components/page-shell";
import { SimpleListCard } from "@/components/simple-list-card";

export default function ExamModePage() {
  return (
    <PageShell>
      <SimpleListCard
        eyebrow="Exam Mode"
        title="Fast paths for peak traffic"
        description="The UI is already shaped for cache-first answering, shorter outputs, and quick 1 mark / 3 marks / 5 marks access."
        items={[
          "1 Mark: fastest cached or template-backed answer path",
          "3 Marks: short exam paragraph with citations",
          "5 Marks: structured explanation with citation chips",
        ]}
      />
    </PageShell>
  );
}
