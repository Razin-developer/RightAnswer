export function sanitizeQuestion(question: string) {
  return question.replace(/[{}<>`]/g, " ").replace(/\s+/g, " ").trim();
}

export function toQuestionTokens(question: string) {
  return question
    .toLowerCase()
    .split(/\s+/)
    .map((token) => token.replace(/[^\p{L}\p{N}]/gu, ""))
    .filter(Boolean);
}

export function detectDifficulty(question: string) {
  const lower = question.toLowerCase();
  if (lower.includes("why") || lower.includes("compare") || lower.includes("difference")) {
    return "hard";
  }
  if (lower.includes("define") || lower.includes("what is")) {
    return "simple";
  }
  return "medium";
}

export function detectContentPreference(question: string) {
  const lower = question.toLowerCase();
  if (lower.includes("diagram")) return "diagram_ref";
  if (lower.includes("graph")) return "graph_ref";
  if (lower.includes("table")) return "table_ref";
  if (lower.includes("define")) return "definition";
  if (lower.includes("exercise")) return "question";
  return "paragraph";
}
