/// Thrown by a non-streaming AI service call (exam/study-plan generation)
/// when the backend's `/api/ai/chat` responds with `needsBetaConfirmation`
/// instead of an answer — the best-matching content came from a chapter
/// that hasn't been fully verified yet. Mirrors the same beta-gate the
/// chat screen already handles via its streaming `needsBetaConfirmation`
/// event; this is the equivalent for callers using the plain
/// request/response path.
class BetaConfirmationRequiredException implements Exception {
  final String? chapterId;
  final String? chapterName;
  final String? subjectName;
  final String message;

  const BetaConfirmationRequiredException({
    this.chapterId,
    this.chapterName,
    this.subjectName,
    required this.message,
  });

  /// Returns the exception if [decoded] is a beta-confirmation response
  /// shape, else null — callers check this right after decoding a
  /// postChatCompletions response, before touching `choices`.
  static BetaConfirmationRequiredException? fromResponse(
    Map<String, dynamic> decoded,
  ) {
    if (decoded['needsBetaConfirmation'] != true) return null;
    final chapterName = decoded['chapterName'] as String?;
    final subjectName = decoded['subjectName'] as String?;
    final label = [
      chapterName,
      subjectName,
    ].where((v) => v != null && v.isNotEmpty).join(' from ');
    return BetaConfirmationRequiredException(
      chapterId: decoded['chapterId'] as String?,
      chapterName: chapterName,
      subjectName: subjectName,
      message:
          decoded['message'] as String? ??
          '${label.isEmpty ? 'That content' : '"$label"'} is still in beta. Do you want the response anyway?',
    );
  }
}
