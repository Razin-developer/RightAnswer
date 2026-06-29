import 'tool_types.dart';

class Prompts {
  static const String systemPrompt = '''You are a school tutor.
Answer only using the provided selected chapter context.
Do not use outside knowledge.
If the answer is not available in the context, say:
"This is not covered in the selected chapter."
Answer in the requested language.
Keep the answer suitable for the selected grade/class.
Be clear, accurate, and student-friendly.''';

  static String taskPrompt(String toolType, String? question) {
    switch (toolType) {
      case ToolType.explainSimple:
        final topic = (question != null && question.isNotEmpty) ? question : 'the main topic';
        return 'Explain "$topic" in simple language using only the chapter context. Use examples only if they are supported by the context.';

      case ToolType.chapterSummary:
        return 'Create a clear chapter summary using only the chapter context. Include headings and important points.';

      case ToolType.quiz:
        return 'Create a quiz from the chapter context. Include mixed question types and provide answers separately at the end.';

      case ToolType.mcq:
        return 'Create multiple-choice questions from the chapter context. Each question must have 4 options (A, B, C, D), one correct answer marked, and a short explanation.';

      case ToolType.trueFalse:
        return 'Create true/false questions from the chapter context. Include answer key and short explanation for each.';

      case ToolType.fillBlanks:
        return 'Create fill-in-the-blanks questions from the chapter context. Include answer key at the end.';

      case ToolType.flashcards:
        return 'Create flashcards from the chapter context. Format each card as:\n**Front:** [concept/term]\n**Back:** [definition/explanation]';

      case ToolType.shortAnswer:
        return 'Create short-answer questions from the chapter context. Include model answers (2–4 sentences each).';

      case ToolType.longAnswer:
        return 'Create long-answer questions from the chapter context. Include structured model answers with headings and points.';

      case ToolType.revisionNotes:
        return 'Create revision notes from the chapter context. Use headings, bullets, and exam-focused points.';

      case ToolType.keyPoints:
        return 'Extract the key points from the chapter context. Format as a numbered list.';

      case ToolType.importantFormulas:
        return 'Extract important formulas from the chapter context. Format each as: **Formula Name:** formula and explanation. If no formulas are found, say no formulas are covered in this selected chapter.';

      case ToolType.importantDefinitions:
        return 'Extract important definitions from the chapter context. Format as **Term:** Definition.';

      case ToolType.learningObjectives:
        return 'Generate learning objectives based only on the chapter context. Format as: "By the end of this chapter, students will be able to..."';

      default:
        return 'Analyze the chapter context and provide a helpful response.';
    }
  }

  static String buildFullPrompt({
    required String toolType,
    required String? question,
    required List<String> contextChunks,
    required String language,
    required String gradeLevel,
    required String tone,
    required String outputLength,
  }) {
    final chunkText = contextChunks
        .asMap()
        .entries
        .map((e) => '[Chunk ${e.key + 1}]\n${e.value}')
        .join('\n\n---\n\n');

    final task = taskPrompt(toolType, question);
    final lengthGuide = _outputLengthGuide(outputLength);
    final toneGuide = _toneGuide(tone);

    return '''$task

Grade/Class Level: $gradeLevel
Tone: $toneGuide
Output Length: $lengthGuide
Answer Language: $language

--- CHAPTER CONTEXT START ---

$chunkText

--- CHAPTER CONTEXT END ---''';
  }

  static String _toneGuide(String tone) {
    switch (tone) {
      case 'simple': return 'Simple and easy to understand, avoid jargon';
      case 'detailed': return 'Detailed and thorough with full explanations';
      default: return 'Normal academic tone';
    }
  }

  static String _outputLengthGuide(String length) {
    switch (length) {
      case 'short': return 'Short and concise';
      case 'long': return 'Long and comprehensive';
      default: return 'Medium length';
    }
  }
}
