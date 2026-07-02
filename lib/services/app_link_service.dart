import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../app/app_router.dart';
import '../config/app_config.dart';
import '../models/app_exception.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/import_export_service.dart';
import '../screens/main_screen.dart';

class AppLinkService {
  static final AppLinkService instance = AppLinkService._();
  AppLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  Uri? _pendingUri;
  bool _initialized = false;
  bool _handling = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        unawaited(handleUri(initialUri));
      }
    } catch (_) {
      // Ignore malformed initial links.
    }

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(handleUri(uri)),
      onError: (_) {},
    );
  }

  Future<void> retryPendingLinkIfPossible() async {
    final pending = _pendingUri;
    if (pending == null) {
      return;
    }
    _pendingUri = null;
    await handleUri(pending);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }

  Future<void> handleUri(Uri uri) async {
    final target = _parseUri(uri);
    if (target == null || _handling) {
      return;
    }

    if (navigatorKey.currentState == null) {
      _pendingUri = uri;
      return;
    }

    _handling = true;
    try {
      try {
        switch (target.kind) {
          case _LinkKind.chat:
            await _openSharedChat(target);
            break;
          case _LinkKind.subject:
          case _LinkKind.chapter:
          case _LinkKind.content:
          case _LinkKind.studyPlan:
          case _LinkKind.exam:
          case _LinkKind.quiz:
            await _importSharedContent(target);
            break;
          case _LinkKind.unknown:
            await _openUnknownShare(target);
            break;
        }
      } catch (error) {
        _showMessage(
          'Could not open shared link: ${AppException.from(error).message}',
        );
      }
    } finally {
      _handling = false;
    }
  }

  Future<void> _openSharedChat(_LinkTarget target) async {
    if (!AuthService.instance.isLoggedIn) {
      _pendingUri = target.sourceUri;
      _showMessage('Sign in to open this shared chat.');
      return;
    }

    final joined = await CloudSyncService.instance.joinChatFromShareToken(
      target.token,
    );
    _navigateToRoot(
      MainScreen(initialTabIndex: 0, initialChatId: joined.localChatId),
    );
    _showMessage('Opened shared chat.');
  }

  Future<void> _importSharedContent(_LinkTarget target) async {
    if (!ConnectivityService.instance.isOnline) {
      throw AppException.network('Connect to the internet to open this link.');
    }

    final imported = await ImportExportService.instance.importFromBytes(
      await CloudSyncService.instance.downloadContentZip(target.downloadUrl),
    );

    final initialTab = switch (target.kind) {
      _LinkKind.studyPlan => 2,
      _LinkKind.exam => 1,
      _LinkKind.quiz => 1,
      _ => 3,
    };

    _navigateToRoot(
      MainScreen(
        initialTabIndex: initialTab,
        initialSubjectId: imported.subjectIds.isNotEmpty
            ? imported.subjectIds.first
            : null,
        initialChapterId: imported.chapterIds.length == 1
            ? imported.chapterIds.first
            : null,
        initialStudyPlanId: imported.studyPlanIds.length == 1
            ? imported.studyPlanIds.first
            : null,
      ),
    );

    if (imported.subjects > 0 || imported.chapters > 0) {
      _showMessage(
        'Imported ${imported.subjects} subject(s) and ${imported.chapters} chapter(s).',
      );
      return;
    }
    if (imported.studyPlans > 0) {
      _showMessage('Imported ${imported.studyPlans} study plan(s).');
      return;
    }
    if (imported.exams > 0) {
      _showMessage('Imported ${imported.exams} exam(s).');
    }
  }

  Future<void> _openUnknownShare(_LinkTarget target) async {
    try {
      await _importSharedContent(target);
      return;
    } catch (_) {
      if (!AuthService.instance.isLoggedIn) {
        _pendingUri = target.sourceUri;
        _showMessage('Sign in to open this shared link.');
        return;
      }
    }

    await _openSharedChat(target.copyWith(kind: _LinkKind.chat));
  }

  void _navigateToRoot(Widget screen) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  void _showMessage(String message) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  _LinkTarget? _parseUri(Uri uri) {
    if (uri.scheme == 'rightanswer') {
      final segments = <String>[
        if (uri.host.isNotEmpty) uri.host,
        ...uri.pathSegments.where((segment) => segment.isNotEmpty),
      ];
      if (segments.length >= 3 && segments.first == 'share') {
        return _buildTypedTarget(
          kindText: segments[1],
          token: segments[2],
          sourceUri: uri,
        );
      }
      if (segments.length >= 2) {
        return _buildTypedTarget(
          kindText: segments[0],
          token: segments[1],
          sourceUri: uri,
        );
      }
      return null;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length >= 3 && segments[0] == 'share') {
      return _buildTypedTarget(
        kindText: segments[1],
        token: segments[2],
        sourceUri: uri,
      );
    }
    if (segments.length >= 3 &&
        segments[0] == 'api' &&
        segments[1] == 'share') {
      return _LinkTarget(
        kind: _LinkKind.unknown,
        token: segments[2],
        downloadUrl: uri.toString(),
        sourceUri: uri,
      );
    }
    return null;
  }

  _LinkTarget _buildTypedTarget({
    required String kindText,
    required String token,
    required Uri sourceUri,
  }) {
    final normalizedKind = kindText.toLowerCase();
    final kind = switch (normalizedKind) {
      'chat' => _LinkKind.chat,
      'subject' => _LinkKind.subject,
      'chapter' => _LinkKind.chapter,
      'content' => _LinkKind.content,
      'study-plan' => _LinkKind.studyPlan,
      'study_plan' => _LinkKind.studyPlan,
      'plan' => _LinkKind.studyPlan,
      'exam' => _LinkKind.exam,
      'quiz' => _LinkKind.quiz,
      'quizzes' => _LinkKind.quiz,
      _ => _LinkKind.unknown,
    };

    return _LinkTarget(
      kind: kind,
      token: token,
      sourceUri: sourceUri,
      downloadUrl: _buildDownloadUrl(sourceUri, token),
    );
  }

  String _buildDownloadUrl(Uri sourceUri, String token) {
    if (sourceUri.scheme == 'http' || sourceUri.scheme == 'https') {
      return '${sourceUri.scheme}://${sourceUri.authority}/api/share/$token';
    }

    final base = AppConfig.appUrl.trim().isNotEmpty
        ? AppConfig.appUrl.trim()
        : AppConfig.apiUrl.trim();
    return '$base/api/share/$token';
  }
}

enum _LinkKind {
  chat,
  content,
  subject,
  chapter,
  studyPlan,
  exam,
  quiz,
  unknown,
}

class _LinkTarget {
  final _LinkKind kind;
  final String token;
  final String downloadUrl;
  final Uri sourceUri;

  const _LinkTarget({
    required this.kind,
    required this.token,
    required this.downloadUrl,
    required this.sourceUri,
  });

  _LinkTarget copyWith({
    _LinkKind? kind,
    String? token,
    String? downloadUrl,
    Uri? sourceUri,
  }) {
    return _LinkTarget(
      kind: kind ?? this.kind,
      token: token ?? this.token,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      sourceUri: sourceUri ?? this.sourceUri,
    );
  }
}
