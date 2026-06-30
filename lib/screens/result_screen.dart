import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:uuid/uuid.dart';
import '../constants/tool_types.dart';
import '../models/chunk.dart';
import '../models/saved_output.dart';
import '../repositories/saved_output_repository.dart';
import '../services/openai_service.dart';

class ResultScreen extends StatefulWidget {
  final GenerationResult result;
  final String toolType;
  final String? question;
  final List<Chunk> usedChunks;
  final String chapterId;
  final String subjectId;
  final String language;

  const ResultScreen({
    super.key,
    required this.result,
    required this.toolType,
    this.question,
    required this.usedChunks,
    required this.chapterId,
    required this.subjectId,
    required this.language,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _repo = SavedOutputRepository();
  bool _saved = false;
  bool _showChunks = false;

  Future<void> _save() async {
    await _repo.insert(
      SavedOutput(
        id: Uuid().v4(),
        subjectId: widget.subjectId,
        chapterId: widget.chapterId,
        toolType: widget.toolType,
        question: widget.question,
        answer: widget.result.answer,
        language: widget.language,
        usedChunkIds: widget.usedChunks.map((c) => c.id).toList(),
        createdAt: DateTime.now(),
      ),
    );
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved successfully!')));
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.result.answer));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.result;

    return Scaffold(
      appBar: AppBar(
        title: Text(ToolType.displayName(widget.toolType)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy',
            onPressed: _copy,
          ),
          IconButton(
            icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_add_outlined),
            tooltip: _saved ? 'Saved' : 'Save',
            onPressed: _saved ? null : _save,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Token / cost bar ──────────────────────────────────────────
          Container(
            color: theme.colorScheme.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _statChip(context, Icons.input, '${r.inputTokens} in'),
                const SizedBox(width: 6),
                _statChip(context, Icons.output, '${r.outputTokens} out'),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.language,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Question banner ───────────────────────────────────────────
          if (widget.question != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.4,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 14,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.question!,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Markdown answer ───────────────────────────────────────────
          Expanded(
            child: Markdown(
              data: widget.result.answer,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                h1: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                h2: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                h3: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                code: TextStyle(
                  fontFamily: 'monospace',
                  backgroundColor: theme.colorScheme.surfaceContainer,
                  fontSize: 13,
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.2,
                  ),
                ),
              ),
            ),
          ),

          // ── Used chunks expander ──────────────────────────────────────
          Divider(height: 1, color: theme.dividerColor),
          InkWell(
            onTap: () => setState(() => _showChunks = !_showChunks),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.usedChunks.length} context chunks used',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showChunks ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
          if (_showChunks)
            Container(
              height: 180,
              color: theme.colorScheme.surfaceContainerLowest,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: widget.usedChunks.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final c = widget.usedChunks[i];
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chunk ${c.chunkIndex + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.text.length > 200
                              ? '${c.text.substring(0, 200)}…'
                              : c.text,
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _statChip(BuildContext context, IconData icon, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
