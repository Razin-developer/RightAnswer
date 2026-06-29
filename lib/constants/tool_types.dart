class ToolType {
  static const String explainSimple = 'EXPLAIN_SIMPLE';
  static const String chapterSummary = 'CHAPTER_SUMMARY';
  static const String quiz = 'QUIZ';
  static const String mcq = 'MCQ';
  static const String trueFalse = 'TRUE_FALSE';
  static const String fillBlanks = 'FILL_BLANKS';
  static const String flashcards = 'FLASHCARDS';
  static const String shortAnswer = 'SHORT_ANSWER';
  static const String longAnswer = 'LONG_ANSWER';
  static const String revisionNotes = 'REVISION_NOTES';
  static const String keyPoints = 'KEY_POINTS';
  static const String importantFormulas = 'IMPORTANT_FORMULAS';
  static const String importantDefinitions = 'IMPORTANT_DEFINITIONS';
  static const String learningObjectives = 'LEARNING_OBJECTIVES';

  static String displayName(String toolType) {
    switch (toolType) {
      case explainSimple: return 'Explain Topic';
      case chapterSummary: return 'Chapter Summary';
      case quiz: return 'Quiz';
      case mcq: return 'MCQs';
      case trueFalse: return 'True / False';
      case fillBlanks: return 'Fill in the Blanks';
      case flashcards: return 'Flashcards';
      case shortAnswer: return 'Short Answer Q&A';
      case longAnswer: return 'Long Answer Q&A';
      case revisionNotes: return 'Revision Notes';
      case keyPoints: return 'Key Points';
      case importantFormulas: return 'Important Formulas';
      case importantDefinitions: return 'Important Definitions';
      case learningObjectives: return 'Learning Objectives';
      default: return toolType;
    }
  }

  static List<String> all = [
    explainSimple,
    chapterSummary,
    quiz,
    mcq,
    trueFalse,
    fillBlanks,
    flashcards,
    shortAnswer,
    longAnswer,
    revisionNotes,
    keyPoints,
    importantFormulas,
    importantDefinitions,
    learningObjectives,
  ];
}
