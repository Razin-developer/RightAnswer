import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../constants/tool_types.dart';
import '../models/saved_output.dart';
import '../repositories/saved_output_repository.dart';

class SavedOutputsScreen extends StatefulWidget {
  const SavedOutputsScreen({super.key});

  @override
  State<SavedOutputsScreen> createState() => _SavedOutputsScreenState();
}

class _SavedOutputsScreenState extends State<SavedOutputsScreen> {
  final _repo = SavedOutputRepository();
  List<SavedOutput> _outputs = [];
  bool _loading = true;
  String? _filterToolType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final outputs = await _repo.getAll(toolType: _filterToolType);
    if (mounted) setState(() { _outputs = outputs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Outputs'),
        actions: [
          if (_filterToolType != null)
            IconButton(
              icon: const Icon(Icons.filter_list_off),
              tooltip: 'Clear filter',
              onPressed: () { setState(() => _filterToolType = null); _load(); },
            ),
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onSelected: (v) { setState(() => _filterToolType = v); _load(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All Types')),
              ...ToolType.all.map((t) => PopupMenuItem(
                    value: t,
                    child: Text(ToolType.displayName(t)),
                  )),
            ],
          ),
          const SizedBox(width: 4),
        ],
        bottom: _filterToolType != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: Container(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    'Filtered: ${ToolType.displayName(_filterToolType!)}',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                  ),
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _outputs.isEmpty
              ? _emptyState(theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    itemCount: _outputs.length,
                    itemBuilder: (ctx, i) => _outputCard(_outputs[i], theme),
                  ),
                ),
    );
  }

  Widget _emptyState(ThemeData theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.bookmark_border, size: 40, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text('No saved outputs',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Generate content and save it to see it here',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
          ],
        ),
      );

  Widget _outputCard(SavedOutput o, ThemeData theme) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => _OutputDetailScreen(output: o))),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(ToolType.displayName(o.toolType),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary)),
                      ),
                      const Spacer(),
                      Text(_fmtDate(o.createdAt),
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        iconSize: 18,
                        icon: Icon(Icons.more_vert,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                        onSelected: (v) {
                          if (v == 'delete') { _repo.delete(o.id); _load(); }
                          if (v == 'copy') {
                            Clipboard.setData(ClipboardData(text: o.answer));
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text('Copied!')));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'copy', child: Text('Copy')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                  if (o.subjectName != null || o.chapterTitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      [o.subjectName, o.chapterTitle].whereType<String>().join(' › '),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                  if (o.question != null) ...[
                    const SizedBox(height: 4),
                    Text('Q: ${o.question}',
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    o.answer.length > 120 ? '${o.answer.substring(0, 120)}…' : o.answer,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  String _fmtDate(DateTime dt) =>
      '${dt.day}/${dt.month}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Detail screen ─────────────────────────────────────────────────────────────

class _OutputDetailScreen extends StatelessWidget {
  final SavedOutput output;
  const _OutputDetailScreen({required this.output});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(ToolType.displayName(output.toolType)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: output.answer));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Copied!')));
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (output.subjectName != null || output.chapterTitle != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                [output.subjectName, output.chapterTitle].whereType<String>().join(' › '),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          if (output.question != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 14, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(output.question!,
                        style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSecondaryContainer)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Markdown(
              data: output.answer,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              selectable: true,
            ),
          ),
        ],
      ),
    );
  }
}
