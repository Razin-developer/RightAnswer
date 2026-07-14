export type UserRole = "student" | "teacher" | "admin" | "org_owner";
export type AppLanguage = "en" | "ml";
export type ContentLanguage = "en" | "ml" | "mixed";
export type Medium = "en" | "ml";

export type AnswerFormat =
  | "short"
  | "long"
  | "1_mark"
  | "2_mark"
  | "3_mark"
  | "4_mark"
  | "5_mark"
  | "exam_style"
  | "simple_explanation"
  | "malayalam_explanation"
  | "english_explanation"
  | "step_by_step"
  | "table_explanation"
  | "graph_explanation"
  | "diagram_explanation"
  | "key_points"
  | "chapter_summary"
  | "important_questions"
  | "flashcards"
  | "quiz"
  | "teacher_worksheet";

export type VerificationStatus = "gold" | "silver" | "bronze" | "unsafe";
export type CacheLayer =
  | "exact"
  | "semantic"
  | "retrieval"
  | "answer"
  | "verified"
  | "pregenerated"
  | "exam_hot";

export type SubscriptionPlanCode =
  | "free"
  | "student_pro"
  | "exam_pass"
  | "teacher"
  | "tuition_center"
  | "school";

export type ContentType =
  | "chapter_heading"
  | "section_heading"
  | "subsection_heading"
  | "paragraph"
  | "definition"
  | "formula"
  | "table_ref"
  | "graph_ref"
  | "diagram_ref"
  | "activity"
  | "experiment"
  | "exercise"
  | "question"
  | "sub_question"
  | "answer_hint"
  | "summary"
  | "glossary";

export interface Citation {
  chapterTitle: string;
  chapterNumber?: number | null;
  pageNumber: number;
  contentUnitId: string;
  excerpt?: string;
}

export interface AskQuestionInput {
  question: string;
  language: AppLanguage;
  subjectId?: string | null;
  chapterId?: string | null;
  answerType: AnswerFormat;
}

export interface AnswerPayload {
  answerText: string;
  answerType: AnswerFormat;
  language: AppLanguage;
  servedFrom: string;
  confidence: number;
  citations: Citation[];
  modelUsed?: string | null;
  verificationStatus?: VerificationStatus;
}
