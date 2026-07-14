import 'package:flutter/material.dart';
import '../models/app_exception.dart';
import '../constants/tool_types.dart';
import '../models/queued_request.dart';
import '../services/connectivity_service.dart';
import '../services/queue_service.dart';
import '../widgets/app_feedback.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  List<QueuedRequest> _items = [];
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    QueueService.instance.addListener(_onQueueChange);
    _load();
  }

  @override
  void dispose() {
    QueueService.instance.removeListener(_onQueueChange);
    super.dispose();
  }

  void _onQueueChange() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final items = await QueueService.instance.getAll();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _processNow() async {
    if (!ConnectivityService.instance.isOnline) {
      AppFeedback.showToast(context, 'No internet connection');
      return;
    }
    setState(() => _processing = true);
    try {
      await QueueService.instance.processQueue();
    } catch (e) {
      if (mounted) {
        await AppFeedback.showErrorDialog(context, AppException.from(e));
      }
    }
    if (mounted) {
      setState(() => _processing = false);
    }
    _load();
  }

  Future<void> _retry(QueuedRequest r) async {
    await QueueService.instance.retry(r.id);
    _load();
  }

  Future<void> _delete(QueuedRequest r) async {
    await QueueService.instance.delete(r.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = _items.where((i) => i.status == 'pending').length;
    final online = ConnectivityService.instance.isOnline;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          if (_items.any((i) => i.status == 'done'))
            TextButton(
              onPressed: () async {
                await QueueService.instance.clearDone();
                _load();
              },
              child: const Text('Clear done'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Status banner ──────────────────────────────────────────────
          _StatusBanner(online: online, pending: pending),

          // ── Process now button ─────────────────────────────────────────
          if (pending > 0 && online)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: FilledButton.icon(
                onPressed: _processing ? null : _processNow,
                icon: _processing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  _processing ? 'Processing…' : 'Process $pending pending now',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? _emptyState(theme)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) => _itemCard(_items[i], theme),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 64,
          color: Colors.green.shade400,
        ),
        const SizedBox(height: 16),
        Text(
          'Queue is empty',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Requests generated while offline appear here',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    ),
  );

  Widget _itemCard(QueuedRequest r, ThemeData theme) {
    final (icon, color, label) = _statusMeta(r.status, theme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 12, color: color),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ToolType.displayName(r.toolType),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _fmtDate(r.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (r.subjectName != null || r.chapterTitle != null)
                Text(
                  [
                    r.subjectName,
                    r.chapterTitle,
                  ].whereType<String>().join(' › '),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              if (r.question != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Q: ${r.question}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              if (r.errorMessage != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    r.errorMessage!,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (r.status == 'failed')
                    OutlinedButton.icon(
                      onPressed: () => _retry(r),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const Spacer(),
                  if (r.status != 'processing')
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      onPressed: () => _delete(r),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color, String) _statusMeta(String status, ThemeData t) =>
      switch (status) {
        'pending' => (Icons.schedule, Colors.orange, 'Pending'),
        'processing' => (Icons.sync, Colors.blue, 'Processing'),
        'done' => (Icons.check_circle, Colors.green, 'Done'),
        'failed' => (Icons.error_outline, Colors.red, 'Failed'),
        _ => (Icons.help_outline, t.colorScheme.onSurface, status),
      };

  String _fmtDate(DateTime dt) =>
      '${dt.day}/${dt.month}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final bool online;
  final int pending;
  const _StatusBanner({required this.online, required this.pending});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (online && pending == 0) {
      return Container(
        width: double.infinity,
        color: Colors.green.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.wifi, size: 16, color: Colors.green),
            const SizedBox(width: 8),
            const Text(
              'Online — queue is empty',
              style: TextStyle(fontSize: 13, color: Colors.green),
            ),
          ],
        ),
      );
    }
    if (!online) {
      return Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 16, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              pending > 0
                  ? 'Offline — $pending ${pending == 1 ? 'request' : 'requests'} waiting'
                  : 'Offline — new requests will be queued',
              style: const TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.wifi, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'Online — $pending ${pending == 1 ? 'request' : 'requests'} ready to process',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

/// Compact offline/queue indicator widget — embed in any screen's AppBar actions.
class ConnectivityChip extends StatefulWidget {
  final VoidCallback? onTap;
  const ConnectivityChip({super.key, this.onTap});

  @override
  State<ConnectivityChip> createState() => _ConnectivityChipState();
}

class _ConnectivityChipState extends State<ConnectivityChip> {
  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.isOnlineNotifier.addListener(_rebuild);
    QueueService.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    ConnectivityService.instance.isOnlineNotifier.removeListener(_rebuild);
    QueueService.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final online = ConnectivityService.instance.isOnline;
    final pending = QueueService.instance.pendingCount;

    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              online ? Icons.wifi : Icons.wifi_off,
              size: 22,
              color: online ? Colors.green : Colors.orange,
            ),
            if (pending > 0)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    pending > 9 ? '9+' : '$pending',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
