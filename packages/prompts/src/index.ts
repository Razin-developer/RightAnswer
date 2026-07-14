import type { AnswerFormat, AppLanguage, Citation } from "@right-answer/types";

const answerTypeRules: Record<AnswerFormat, string> = {
  short: "Return a concise SSLC-friendly answer.",
  long: "Return a detailed but still exam-appropriate answer.",
  "1_mark": "Return exactly one crisp exam-ready sentence unless two clauses are necessary.",
  "2_mark": "Return two concise points or one short sentence plus one supporting point.",
  "3_mark": "Return a short exam-style paragraph or three clear points.",
  "4_mark": "Return four clear points or a short structured explanation.",
  "5_mark": "Return a brief introduction, key points, and a short conclusion.",
  exam_style: "Return an exam-style answer aligned to the requested question.",
  simple_explanation: "Explain in simple language for a Class 10 student.",
  malayalam_explanation:
    "Write fully in Malayalam, preserving important textbook terms when needed.",
  english_explanation:
    "Use clear SSLC-friendly English and avoid unnecessary advanced terminology.",
  step_by_step:
    "Return ordered steps and mention if any step is inferred rather than directly stated.",
  table_explanation:
    "Explain what the table shows, the important comparisons, and one likely exam takeaway.",
  graph_explanation:
    "Explain the graph type, axes, trend, and likely textbook interpretation.",
  diagram_explanation:
    "Name the diagram, explain labeled parts, and mention one common exam angle.",
  key_points: "Return compact revision points that are easy to remember.",
  chapter_summary: "Return concise chapter study notes organized by major concepts.",
  important_questions:
    "Generate likely textbook-grounded exam questions across definitions, processes, diagrams, and exercises.",
  flashcards:
    "Return JSON-style flashcards with short question-answer pairs and citation references.",
  quiz: "Return a balanced quiz with objective and short-answer questions grounded in the textbook.",
  teacher_worksheet:
    "Generate a worksheet with mixed mark questions and keep the wording textbook-grounded.",
};

export function buildGroundedPrompt(params: {
  language: AppLanguage;
  answerType: AnswerFormat;
  question: string;
  context: string;
  citations: Citation[];
}): string {
  return [
    "You are generating a Kerala SSLC textbook-grounded answer.",
    "Use only the provided textbook context.",
    "If the answer is not clearly present, say that clearly and provide the closest useful explanation.",
    `Return the answer in ${params.language}.`,
    answerTypeRules[params.answerType],
    "Do not copy long textbook passages.",
    `Question: ${params.question}`,
    `Context: ${params.context}`,
    `Citations: ${params.citations.map((citation) => `${citation.chapterTitle} page ${citation.pageNumber}`).join("; ")}`,
  ].join("\n");
}
