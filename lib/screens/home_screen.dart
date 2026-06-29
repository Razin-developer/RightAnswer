import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/subject.dart';
import '../repositories/subject_repository.dart';
import '../services/connectivity_service.dart';
import 'queue_screen.dart';
import 'subject_screen.dart';
import 'saved_outputs_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = SubjectRepository();
  List<Subject> _subjects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final subjects = await _repo.getAll();
    if (mounted) setState(() { _subjects = subjects; _loading = false; });
  }

  Future<void> _addSubject() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddDialog(
        title: 'New Subject',
        hint: 'e.g. Physics, Biology, History',
        label: 'Subject name',
        controller: ctrl,
      ),
    );
    if (name == null || name.isEmpty) return;
    await _repo.insert(Subject(id: Uuid().v4(), name: name, createdAt: DateTime.now()));
    _load();
  }

  Future<void> _deleteSubject(Subject s) async {
    final ok = await _confirmDelete(
        context, 'Delete Subject', '"${s.name}" and all its chapters will be permanently removed.');
    if (!ok) return;
    await _repo.delete(s.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.auto_stories, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('RightAnswer'),
          ],
        ),
        actions: [
          ConnectivityChip(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const QueueScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'Saved Outputs',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SavedOutputsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => setState(() {})),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _OfflineBanner(onViewQueue: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const QueueScreen()))),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _subjects.isEmpty
                    ? _emptyState(theme)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _subjects.length,
                          itemBuilder: (ctx, i) => _subjectCard(_subjects[i], i, theme),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSubject,
        icon: const Icon(Icons.add),
        label: const Text('Add Subject'),
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
              child: Icon(Icons.library_books_outlined,
                  size: 40, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text('No subjects yet',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Create your first subject to get started',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _addSubject,
              icon: const Icon(Icons.add),
              label: const Text('Add Subject'),
            ),
          ],
        ),
      );

  Widget _subjectCard(Subject s, int i, ThemeData theme) {
    const iconColors = [
      Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFF059669),
      Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF0891B2),
    ];
    final color = iconColors[i % iconColors.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SubjectScreen(subject: s)))
              .then((_) => _load()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.subject, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Created ${_fmtDate(s.createdAt)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                  onSelected: (v) { if (v == 'delete') _deleteSubject(s); },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

// ── Offline banner ────────────────────────────────────────────────────────────

class _OfflineBanner extends StatefulWidget {
  final VoidCallback onViewQueue;
  const _OfflineBanner({required this.onViewQueue});

  @override
  State<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<_OfflineBanner> {
  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.isOnlineNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    ConnectivityService.instance.isOnlineNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    if (ConnectivityService.instance.isOnline) return const SizedBox.shrink();
    return GestureDetector(
      onTap: widget.onViewQueue,
      child: Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 15, color: Colors.orange),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('You\'re offline — study tools will be queued',
                  style: TextStyle(fontSize: 12, color: Colors.orange)),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Colors.orange),
          ],
        ),
      ),
    );
  }
}

// ── Shared dialog ────────────────────────────────────────────────────────────

class _AddDialog extends StatelessWidget {
  final String title;
  final String label;
  final String hint;
  final TextEditingController controller;

  const _AddDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint),
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

Future<bool> _confirmDelete(BuildContext ctx, String title, String body) async {
  final result = await showDialog<bool>(
    context: ctx,
    builder: (dlgCtx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(dlgCtx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result == true;
}
