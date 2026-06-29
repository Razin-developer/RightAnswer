import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/chunk.dart';
import '../repositories/chunk_repository.dart';

/// Handles text splitting, local keyword search, and cosine similarity retrieval.
class RetrievalService {
  final ChunkRepository _chunkRepo;
  static const int _chunkSize = 400; // approximate words per chunk
  static const int _chunkOverlap = 50; // overlapping words between chunks
  static const int _topK = 8; // number of chunks to return

  RetrievalService(this._chunkRepo);

  /// Splits text into overlapping word-window chunks.
  List<String> splitIntoChunks(String text) {
    final words = text.split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return [];

    final chunks = <String>[];
    int start = 0;
    while (start < words.length) {
      final end = min(start + _chunkSize, words.length);
      chunks.add(words.sublist(start, end).join(' '));
      if (end == words.length) break;
      start += _chunkSize - _chunkOverlap;
    }
    return chunks;
  }

  /// Creates Chunk models from raw text, deletes old chunks, inserts new ones.
  Future<List<Chunk>> processAndStoreChunks(String chapterId, String text) async {
    final rawChunks = splitIntoChunks(text);
    final uuid = Uuid();
    final now = DateTime.now();

    final chunks = rawChunks.asMap().entries.map((e) => Chunk(
      id: uuid.v4(),
      chapterId: chapterId,
      chunkIndex: e.key,
      text: e.value,
      createdAt: now,
    )).toList();

    await _chunkRepo.deleteByChapter(chapterId);
    await _chunkRepo.insertAll(chunks);
    return chunks;
  }

  /// Retrieves top chunks from a chapter using keyword scoring (always),
  /// falling back to cosine similarity if embeddings are present.
  Future<List<Chunk>> searchChapter(String chapterId, String query) async {
    final allChunks = await _chunkRepo.getByChapter(chapterId);
    if (allChunks.isEmpty) return [];

    final hasEmbeddings = allChunks.any((c) => c.embedding != null);

    if (hasEmbeddings && query.isNotEmpty) {
      // Cosine similarity requires a query embedding — handled by OpenAIService
      // For now fall through to keyword scoring
    }

    return _keywordScore(allChunks, query);
  }

  /// Scores chunks by keyword overlap with query, returns top-K.
  List<Chunk> _keywordScore(List<Chunk> chunks, String query) {
    if (query.isEmpty) {
      // No query — return first N chunks (for summary-style tools)
      return chunks.take(_topK).toList();
    }

    final queryWords = _tokenize(query);
    if (queryWords.isEmpty) return chunks.take(_topK).toList();

    final scored = chunks.map((c) {
      final chunkWords = _tokenize(c.text);
      final score = queryWords
          .where((w) => chunkWords.contains(w))
          .length
          .toDouble();
      return _ScoredChunk(c, score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(_topK).map((s) => s.chunk).toList();
  }

  Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();
  }

  /// Cosine similarity between two equal-length vectors.
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    return denom == 0 ? 0 : dot / denom;
  }

  /// Rough token estimate: ~4 chars per token (GPT tokenizer heuristic).
  int estimateTokens(String text) => (text.length / 4).ceil();
}

class _ScoredChunk {
  final Chunk chunk;
  final double score;
  _ScoredChunk(this.chunk, this.score);
}
