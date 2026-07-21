import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_languages.dart';
import '../models/chat.dart';
import '../models/chat_message.dart';
import '../repositories/chat_message_repository.dart';
import '../repositories/chat_repository.dart';
import '../services/auth_service.dart';
import '../services/chat_ai_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/tts_service.dart';
import '../models/app_exception.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_logo.dart';
import '../widgets/chapter_picker.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/rich_answer_view.dart';
import '../widgets/voice_input_sheet.dart';
import 'queue_screen.dart';
import 'saved_outputs_screen.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? initialChatId;

  const ChatScreen({super.key, this.initialChatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatRepo = ChatRepository();
  final _messageRepo = ChatMessageRepository();
  final _tts = TtsService.instance;

  Chat? _currentChat;
  List<ChatMessage> _messages = [];
  List<Chat> _allChats = [];

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isGenerating = false;
  bool _isRecording = false;
  bool _isTemporary = false;
  bool _didConsumeInitialChat = false;

  String? _selectedImagePath;
  String? _selectedResponseLanguage;
  String? _streamingMessageId;
  String _responseLength = 'normal';
  String _reasoningLevel = 'mid';
  // Classification the AI backend attaches to a chat's answers — the client
  // no longer picks a subject/chapter, this is purely informational and is
  // filled in after the first response comes back.
  String? _contextSubjectName;
  String? _contextChapterName;

  // User-picked chapter scoping (via the "+" menu's chapter picker). This is
  // purely optional and additive — when null, retrieval stays global exactly
  // as before. When set, it's sent as `chapterIds: [id]` on the next send.
  String? _selectedChapterId;
  String? _selectedChapterLabel;

  @override
  void initState() {
    super.initState();
    _loadAllChats();
    _tts.initialize();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadAllChats() async {
    final chats = await _chatRepo.getAll();
    if (!mounted) return;
    setState(() => _allChats = chats);

    final initialChatId = widget.initialChatId;
    if (!_didConsumeInitialChat && initialChatId != null) {
      _didConsumeInitialChat = true;
      final match = chats.where((chat) => chat.id == initialChatId).firstOrNull;
      if (match != null) {
        await _loadChat(match);
        return;
      }
    }

    if (_currentChat == null && chats.isNotEmpty) {
      await _loadChat(chats.first);
    }
  }

  Future<void> _loadChat(Chat chat) async {
    final messages = await _messageRepo.getByChatId(chat.id);
    if (!mounted) return;
    setState(() {
      _currentChat = chat;
      _messages = messages;
      _isTemporary = chat.isTemporary;
      _contextSubjectName = chat.subjectName;
      _contextChapterName = chat.chapterNames.isNotEmpty
          ? chat.chapterNames.first
          : null;
      // Manual chapter scoping is a per-compose choice, not saved with the
      // chat — reset it when switching chats.
      _selectedChapterId = null;
      _selectedChapterLabel = null;
    });
    _scrollToBottom();
  }

  void _startNewChat({bool temporary = false}) {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
    setState(() {
      _currentChat = null;
      _messages = [];
      _isTemporary = temporary;
      _inputCtrl.clear();
      _selectedImagePath = null;
      _contextSubjectName = null;
      _contextChapterName = null;
      _selectedChapterId = null;
      _selectedChapterLabel = null;
    });
  }

  Future<void> _sendMessage() async => _sendMessageStreaming();

  Future<void> _sendMessageStreaming() async {
    if (_isGenerating) return;
    final text = _inputCtrl.text.trim();
    if (text.isEmpty && _selectedImagePath == null) {
      AppFeedback.showToast(context, 'Enter a message or attach an image');
      return;
    }
    if (_selectedImagePath != null && !File(_selectedImagePath!).existsSync()) {
      setState(() => _selectedImagePath = null);
      AppFeedback.showToast(
        context,
        'The selected image is no longer available',
      );
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      AppFeedback.showToast(
        context,
        'You are offline. Connect to send a message.',
      );
      return;
    }

    if (_currentChat == null) {
      final now = DateTime.now();
      final newChat = Chat(
        id: const Uuid().v4(),
        name: 'New Chat',
        chapterIds: const [],
        chapterNames: const [],
        isTemporary: _isTemporary,
        createdAt: now,
        updatedAt: now,
      );
      if (!_isTemporary) await _chatRepo.insert(newChat);
      setState(() => _currentChat = newChat);
      if (!_isTemporary) await _loadAllChats();
    }

    final chatId = _currentChat!.id;
    final imagePathCopy = _selectedImagePath;
    final historyBeforeSend = List<ChatMessage>.from(_messages);
    final chosenLanguage = effectiveResponseLanguage(_selectedResponseLanguage);

    final userMsg = ChatMessage(
      id: const Uuid().v4(),
      chatId: chatId,
      role: 'user',
      content: text,
      imagePath: imagePathCopy,
      responseLanguage: chosenLanguage,
      responseLength: _responseLength,
      reasoningLevel: _reasoningLevel,
      tokenCount: 0,
      cost: 0,
      createdAt: DateTime.now(),
    );

    final assistantMsg = ChatMessage(
      id: const Uuid().v4(),
      chatId: chatId,
      role: 'assistant',
      content: '',
      responseLanguage: chosenLanguage,
      responseLength: _responseLength,
      reasoningLevel: _reasoningLevel,
      tokenCount: 0,
      cost: 0,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages = [..._messages, userMsg, assistantMsg];
      _isGenerating = true;
      _streamingMessageId = assistantMsg.id;
      _selectedImagePath = null;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    if (!_isTemporary) await _messageRepo.insert(userMsg);

    await _runAssistantTurn(
      chatId: chatId,
      text: text,
      imagePath: imagePathCopy,
      historyBeforeSend: historyBeforeSend,
      assistantMsg: assistantMsg,
    );
  }

  /// Streams an assistant reply for `assistantMsg` (already appended to
  /// `_messages` as an empty placeholder by the caller) and handles the
  /// three possible outcomes: a normal answer, a network/service error, or
  /// the backend asking for beta-chapter confirmation instead of answering.
  /// On confirmation, replaces the placeholder with a Yes/No prompt and,
  /// if the user says yes, resends the exact same request with
  /// `confirmBetaChapterId` set and recurses into a fresh placeholder.
  Future<void> _runAssistantTurn({
    required String chatId,
    required String text,
    required String? imagePath,
    required List<ChatMessage> historyBeforeSend,
    required ChatMessage assistantMsg,
    String? confirmBetaChapterId,
  }) async {
    try {
      String? classifiedSubjectId;
      String? classifiedSubjectName;
      String? classifiedChapterId;
      String? classifiedChapterName;
      bool betaConfirmationNeeded = false;
      String? betaChapterId;
      String? betaChapterName;
      String? betaSubjectName;
      String? betaMessage;

      await for (final event in ChatAIService.instance.streamMessage(
        userContent: text,
        imagePath: imagePath,
        responseLength: _responseLength,
        reasoningLevel: _reasoningLevel,
        responseLanguage: effectiveResponseLanguage(_selectedResponseLanguage),
        history: historyBeforeSend,
        chapterIds: _selectedChapterId != null ? [_selectedChapterId!] : null,
        confirmBetaChapterId: confirmBetaChapterId,
      )) {
        if (!mounted) return;
        if (event.needsBetaConfirmation) {
          betaConfirmationNeeded = true;
          betaChapterId = event.betaChapterId;
          betaChapterName = event.betaChapterName;
          betaSubjectName = event.betaSubjectName;
          betaMessage = event.betaMessage;
          break;
        }
        setState(() {
          _messages = _messages
              .map(
                (message) => message.id == assistantMsg.id
                    ? message.copyWith(
                        content: event.content,
                        tokenCount: event.inputTokens + event.outputTokens,
                        cost: event.cost,
                        sourceChunks: event.isDone ? event.sourceChunks : null,
                        blocks: event.isDone ? event.blocks : null,
                        sources: event.isDone ? event.sources : null,
                      )
                    : message,
              )
              .toList();
          if (event.isDone) {
            _isGenerating = false;
            _streamingMessageId = null;
            classifiedSubjectId = event.subjectId;
            classifiedSubjectName = event.subjectName;
            classifiedChapterId = event.chapterId;
            classifiedChapterName = event.chapterName;
          }
        });
        _scrollToBottom();
      }

      if (betaConfirmationNeeded) {
        // Drop the empty placeholder — it never received an answer.
        setState(() {
          _messages = _messages
              .where((message) => message.id != assistantMsg.id)
              .toList();
          _isGenerating = false;
          _streamingMessageId = null;
        });
        if (!mounted) return;
        final betaLabel = [
          betaChapterName,
          betaSubjectName,
        ].where((v) => v != null && v.isNotEmpty).join(' from ');
        final confirmed = await _showBetaConfirmationDialog(
          betaMessage ??
              '${betaLabel.isEmpty ? 'That content' : '"$betaLabel"'} is still in beta. Do you want the response anyway?',
        );
        if (!mounted || confirmed != true || betaChapterId == null) return;

        final retryAssistantMsg = ChatMessage(
          id: const Uuid().v4(),
          chatId: chatId,
          role: 'assistant',
          content: '',
          responseLanguage: assistantMsg.responseLanguage,
          responseLength: assistantMsg.responseLength,
          reasoningLevel: assistantMsg.reasoningLevel,
          tokenCount: 0,
          cost: 0,
          createdAt: DateTime.now(),
        );
        setState(() {
          _messages = [..._messages, retryAssistantMsg];
          _isGenerating = true;
          _streamingMessageId = retryAssistantMsg.id;
        });
        _scrollToBottom();
        await _runAssistantTurn(
          chatId: chatId,
          text: text,
          imagePath: imagePath,
          historyBeforeSend: historyBeforeSend,
          assistantMsg: retryAssistantMsg,
          confirmBetaChapterId: betaChapterId,
        );
        return;
      }

      final finalAssistant = _messages.firstWhere(
        (message) => message.id == assistantMsg.id,
      );
      if (finalAssistant.content.trim().isEmpty) {
        throw AppException.service(
          'The AI returned an empty response. Please try again.',
        );
      }

      if (!_isTemporary) {
        await _messageRepo.insert(finalAssistant);
        await _chatRepo.touchUpdatedAt(chatId);
        if (classifiedSubjectName != null) {
          await _chatRepo.updateClassification(
            chatId,
            subjectId: classifiedSubjectId,
            subjectName: classifiedSubjectName,
            chapterId: classifiedChapterId,
            chapterName: classifiedChapterName,
          );
          if (mounted) {
            setState(() {
              _contextSubjectName = classifiedSubjectName;
              _contextChapterName = classifiedChapterName;
              if (_currentChat?.id == chatId) {
                _currentChat = _currentChat!.copyWith(
                  subjectId: classifiedSubjectId,
                  subjectName: classifiedSubjectName,
                  chapterIds: classifiedChapterId == null
                      ? const []
                      : [classifiedChapterId!],
                  chapterNames: classifiedChapterName == null
                      ? const []
                      : [classifiedChapterName!],
                );
              }
            });
          }
        }
        await _loadAllChats();

        final userCount = _messages.where((m) => m.isUser).length;
        if (userCount == 1 && _currentChat?.name == 'New Chat') {
          _autoNameChat(chatId, text);
        }
      }

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .where((message) => message.id != assistantMsg.id)
            .toList();
        _isGenerating = false;
        _streamingMessageId = null;
      });
      await _showAiError(e);
    }
  }

  /// Shows the beta-chapter confirmation prompt sent by the backend when
  /// the best-matching chapter for a question hasn't been fully verified
  /// yet. Returns true for "Yes, answer anyway", false/null for "No".
  Future<bool?> _showBetaConfirmationDialog(String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Beta chapter'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerateStreaming(ChatMessage assistantMsg) async {
    if (!ConnectivityService.instance.isOnline) {
      AppFeedback.showToast(context, 'You are offline. Connect to regenerate.');
      return;
    }

    final idx = _messages.indexOf(assistantMsg);
    if (idx <= 0 || _currentChat == null) return;
    final userMsg = _messages[idx - 1];
    if (!userMsg.isUser) return;

    if (!_isTemporary) await _messageRepo.delete(assistantMsg.id);
    final withoutOld = List<ChatMessage>.from(_messages)..removeAt(idx);
    final replacement = ChatMessage(
      id: const Uuid().v4(),
      chatId: _currentChat!.id,
      role: 'assistant',
      content: '',
      responseLanguage: userMsg.responseLanguage,
      responseLength: userMsg.responseLength,
      reasoningLevel: userMsg.reasoningLevel,
      tokenCount: 0,
      cost: 0,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages = [...withoutOld, replacement];
      _isGenerating = true;
      _streamingMessageId = replacement.id;
    });
    _scrollToBottom();

    try {
      await for (final event in ChatAIService.instance.streamMessage(
        userContent: userMsg.content,
        imagePath: userMsg.imagePath,
        responseLength: userMsg.responseLength,
        reasoningLevel: userMsg.reasoningLevel,
        responseLanguage: userMsg.responseLanguage,
        history: withoutOld.take(idx - 1).toList(),
      )) {
        if (!mounted) return;
        setState(() {
          _messages = _messages
              .map(
                (message) => message.id == replacement.id
                    ? message.copyWith(
                        content: event.content,
                        tokenCount: event.inputTokens + event.outputTokens,
                        cost: event.cost,
                        sourceChunks: event.isDone ? event.sourceChunks : null,
                        blocks: event.isDone ? event.blocks : null,
                        sources: event.isDone ? event.sources : null,
                      )
                    : message,
              )
              .toList();
          if (event.isDone) {
            _isGenerating = false;
            _streamingMessageId = null;
          }
        });
        _scrollToBottom();
      }

      final finalAssistant = _messages.firstWhere(
        (message) => message.id == replacement.id,
      );
      if (finalAssistant.content.trim().isEmpty) {
        throw AppException.service(
          'The AI returned an empty response. Please try again.',
        );
      }
      if (!_isTemporary) await _messageRepo.insert(finalAssistant);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = withoutOld;
        _isGenerating = false;
        _streamingMessageId = null;
      });
      await _showAiError(e);
    }
  }

  Future<void> _openVoiceComposer() async {
    if (_isGenerating) return;
    setState(() => _isRecording = true);
    final spoken = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => VoiceInputSheet(
        title: 'Voice Input',
        initialText: _inputCtrl.text.trim(),
        localeId: speechLocaleForLanguage(_selectedResponseLanguage),
        localeLabel: effectiveResponseLanguage(_selectedResponseLanguage),
      ),
    );
    if (!mounted) return;
    setState(() => _isRecording = false);
    if (spoken == null || spoken.trim().isEmpty) return;
    _inputCtrl.text = spoken.trim();
    _inputCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputCtrl.text.length),
    );
  }

  Future<void> _showAiError(Object error) async {
    final appError = AppException.from(error);
    if (!mounted) return;
    if (appError.type == AppErrorType.validation) {
      AppFeedback.showToast(context, appError.message);
      return;
    }
    await AppFeedback.showErrorDialog(context, appError);
  }

  void _autoNameChat(String chatId, String firstMessage) async {
    try {
      final name = await ChatAIService.instance.generateChatName(firstMessage);
      final safeName = name.trim();
      if (!mounted || safeName.isEmpty) return;

      await _chatRepo.updateName(chatId, safeName);
      await CloudSyncService.instance.updateChat(chatId, {
        'name': safeName,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      setState(
        () => _currentChat = _currentChat?.copyWith(
          name: safeName,
          updatedAt: DateTime.now(),
        ),
      );
      await _loadAllChats();
    } catch (_) {
      // Auto-naming is best-effort; a failure here should never break chat flow.
    }
  }

  Future<void> _regenerate(ChatMessage assistantMsg) async =>
      _regenerateStreaming(assistantMsg);

  Future<void> _deleteChat(String id) async {
    await _chatRepo.delete(id);
    if (_currentChat?.id == id) {
      setState(() {
        _currentChat = null;
        _messages = [];
      });
    }
    await _loadAllChats();
  }

  Future<void> _togglePin(String id, bool pinned) async {
    await _chatRepo.togglePin(id, pinned);
    if (_currentChat?.id == id) {
      setState(() => _currentChat = _currentChat!.copyWith(isPinned: pinned));
    }
    await _loadAllChats();
  }

  Future<void> _shareChat() async {
    if (_currentChat == null || _isTemporary) return;
    if (!AuthService.instance.isLoggedIn) {
      AppFeedback.showToast(context, 'Sign in to share chats');
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      AppFeedback.showToast(context, 'You are offline');
      return;
    }
    try {
      final result = await CloudSyncService.instance.shareChatLink(
        _currentChat!.id,
      );
      final url = result['url'] as String? ?? '';
      if (!mounted) return;
      _showShareLinkDialog(url);
    } catch (e) {
      if (mounted) {
        AppFeedback.showToast(context, 'Failed to create share link');
      }
    }
  }

  void _showShareLinkDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Chat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This link lets others join your chat.\nExpires in 10 minutes.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              AppFeedback.showToast(context, 'Link copied');
            },
          ),
        ],
      ),
    );
  }

  void _showJoinChatDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Chat'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste share link or token',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = ctrl.text.trim();
              if (raw.isEmpty) return;
              Navigator.pop(ctx);
              // Extract token from URL if needed
              final token = raw.contains('/') ? raw.split('/').last : raw;
              try {
                final joinResult = await CloudSyncService.instance
                    .joinChatFromShareToken(token);
                final localId = joinResult.localChatId;
                if (!mounted) return;
                AppFeedback.showToast(context, 'Joined chat successfully');
                await _loadAllChats();
                if (localId.isNotEmpty) {
                  final chat = _allChats
                      .where((c) => c.id == localId)
                      .firstOrNull;
                  if (chat != null) {
                    _loadChat(chat);
                  }
                }
              } catch (e) {
                if (mounted) {
                  AppFeedback.showToast(context, 'Invalid or expired link');
                }
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameChat() async {
    final currentChat = _currentChat;
    if (currentChat == null) return;

    final ctrl = TextEditingController(text: currentChat.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Chat'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Chat name',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || name == null) return;

    final safeName = name.trim();
    if (safeName.isEmpty) {
      AppFeedback.showToast(context, 'Chat name cannot be empty');
      return;
    }
    if (safeName.length > 60) {
      AppFeedback.showToast(context, 'Chat name must be 60 characters or less');
      return;
    }
    if (safeName == currentChat.name) return;

    try {
      final renamedAt = DateTime.now();
      await _chatRepo.updateName(currentChat.id, safeName);
      await CloudSyncService.instance.updateChat(currentChat.id, {
        'name': safeName,
        'updatedAt': renamedAt.toIso8601String(),
      });

      if (!mounted) return;
      setState(() {
        if (_currentChat?.id == currentChat.id) {
          _currentChat = _currentChat!.copyWith(
            name: safeName,
            updatedAt: renamedAt,
          );
        }
      });
      await _loadAllChats();
      if (!mounted) return;
      AppFeedback.showToast(context, 'Chat renamed');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showToast(
        context,
        'Could not rename chat: ${AppException.from(e).message}',
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _selectedImagePath = picked.path);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showToast(
          context,
          'Could not access image: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _toggleVoice() async => _openVoiceComposer();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _insertQuickAction(String prefix) {
    final current = _inputCtrl.text;
    final newText = current.isEmpty ? '$prefix: ' : '$prefix: $current';
    _inputCtrl.text = newText;
    _inputCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: newText.length),
    );
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppFeedback.showToast(context, 'Copied to clipboard');
  }

  Future<void> _openChapterPicker() async {
    Navigator.pop(context); // close the plus menu first
    final result = await showChapterPickerSheet(context);
    if (result == null || !mounted) return;
    setState(() {
      _selectedChapterId = result.chapterId;
      _selectedChapterLabel = result.chapterLabel;
    });
  }

  void _clearSelectedChapter() {
    setState(() {
      _selectedChapterId = null;
      _selectedChapterLabel = null;
    });
  }

  void _openPlusMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PlusMenuSheet(
        responseLength: _responseLength,
        reasoningLevel: _reasoningLevel,
        selectedResponseLanguage:
            effectiveResponseLanguage(_selectedResponseLanguage) ??
            autoResponseLanguageLabel,
        selectedChapterLabel: _selectedChapterLabel,
        onLengthChanged: (v) => setState(() => _responseLength = v),
        onReasoningChanged: (v) => setState(() => _reasoningLevel = v),
        onLanguageChanged: (value) {
          setState(() {
            _selectedResponseLanguage = value == autoResponseLanguageLabel
                ? null
                : value;
          });
        },
        onPickChapter: _openChapterPicker,
        onClearChapter: () {
          Navigator.pop(context);
          _clearSelectedChapter();
        },
        onCamera: () {
          Navigator.pop(context);
          _pickImage(ImageSource.camera);
        },
        onPhotos: () {
          Navigator.pop(context);
          _pickImage(ImageSource.gallery);
        },
        onFiles: () {
          Navigator.pop(context);
          _pickImage(ImageSource.gallery);
        },
        onSolve: () {
          Navigator.pop(context);
          _insertQuickAction('Solve');
        },
        onExplain: () {
          Navigator.pop(context);
          _insertQuickAction('Explain');
        },
        onChapterSummary: () {
          Navigator.pop(context);
          _insertQuickAction('Summarize this chapter');
        },
        onKeyPoints: () {
          Navigator.pop(context);
          _insertQuickAction('Key points of');
        },
        onLearningObjectives: () {
          Navigator.pop(context);
          _insertQuickAction('Learning objectives for');
        },
      ),
    );
  }

  void _openFullscreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenInputScreen(
          controller: _inputCtrl,
          onSend: () {
            Navigator.pop(context);
            _sendMessage();
          },
          isGenerating: _isGenerating,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: _ChatDrawer(
        chats: _allChats,
        currentChatId: _currentChat?.id,
        onSelectChat: (chat) {
          _scaffoldKey.currentState?.closeDrawer();
          _loadChat(chat);
        },
        onNewChat: _startNewChat,
        onTempChat: () => _startNewChat(temporary: true),
        onDeleteChat: _deleteChat,
        onTogglePin: _togglePin,
        onSavedOutputs: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SavedOutputsScreen()),
          );
        },
        onQueue: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QueueScreen()),
          );
        },
        onSettings: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        },
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: GestureDetector(
          onTap: _currentChat != null ? _renameChat : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _currentChat?.name ?? 'RightAnswer',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_currentChat != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          if (_currentChat != null && !_isTemporary)
            IconButton(
              icon: const Icon(Icons.ios_share_outlined),
              tooltip: 'Share Chat',
              onPressed: _shareChat,
            ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Join Chat',
            onPressed: _showJoinChatDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New Chat',
            onPressed: () => _startNewChat(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_isTemporary)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.5,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.flash_on_rounded,
                    size: 14,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Temporary — not saved to history',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _isTemporary = false),
                    child: Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_contextSubjectName != null)
            _ContextBar(
              subjectName: _contextSubjectName,
              chapterName: _contextChapterName,
            ),
          Expanded(
            child: _messages.isEmpty && !_isGenerating
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = _messages[i];
                      return _MessageBubble(
                        message: msg,
                        isStreaming: msg.id == _streamingMessageId,
                        onCopy: () => _copyText(msg.content),
                        onRead: () => _tts.toggle(
                          msg.content,
                          language: msg.responseLanguage,
                        ),
                        onRegenerate: msg.isUser
                            ? null
                            : () => _regenerate(msg),
                        onFullscreen: msg.isUser
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => _FullscreenResponseScreen(
                                    content: msg.content,
                                    blocks: msg.blocks,
                                    sources: msg.sources,
                                    onCopy: () => _copyText(msg.content),
                                  ),
                                ),
                              ),
                        onSources:
                            msg.isUser ||
                                (msg.sourceChunks.isEmpty &&
                                    msg.sources.isEmpty)
                            ? null
                            : () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => _ResourcesSheet(
                                  chunks: msg.sourceChunks,
                                  sources: msg.sources,
                                ),
                              ),
                      );
                    },
                  ),
          ),
          _InputArea(
            inputCtrl: _inputCtrl,
            isGenerating: _isGenerating,
            isRecording: _isRecording,
            selectedImagePath: _selectedImagePath,
            selectedResponseLanguage: effectiveResponseLanguage(
              _selectedResponseLanguage,
            ),
            selectedChapterLabel: _selectedChapterLabel,
            onSend: _sendMessage,
            onVoice: _toggleVoice,
            onRemoveImage: () => setState(() => _selectedImagePath = null),
            onClearLanguage: () =>
                setState(() => _selectedResponseLanguage = null),
            onClearChapter: _clearSelectedChapter,
            onOpenPlus: _openPlusMenu,
            onFullscreen: _openFullscreen,
          ),
        ],
      ),
    );
  }
}

// ── Chat Drawer ───────────────────────────────────────────────────────────────

class _ChatDrawer extends StatefulWidget {
  final List<Chat> chats;
  final String? currentChatId;
  final void Function(Chat) onSelectChat;
  final VoidCallback onNewChat;
  final VoidCallback onTempChat;
  final void Function(String) onDeleteChat;
  final void Function(String, bool) onTogglePin;
  final VoidCallback onSavedOutputs;
  final VoidCallback onQueue;
  final VoidCallback onSettings;

  const _ChatDrawer({
    required this.chats,
    required this.currentChatId,
    required this.onSelectChat,
    required this.onNewChat,
    required this.onTempChat,
    required this.onDeleteChat,
    required this.onTogglePin,
    required this.onSavedOutputs,
    required this.onQueue,
    required this.onSettings,
  });

  @override
  State<_ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<_ChatDrawer> {
  bool _isSearching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Chat> get _filtered {
    if (_query.isEmpty) return widget.chats;
    final q = _query.toLowerCase();
    return widget.chats
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              (c.subjectName?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  Map<String, List<Chat>> _groupByTime(List<Chat> chats) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 7));

    final today = <Chat>[];
    final yesterday = <Chat>[];
    final thisWeek = <Chat>[];
    final older = <Chat>[];

    for (final c in chats) {
      if (!c.updatedAt.isBefore(todayStart)) {
        today.add(c);
      } else if (!c.updatedAt.isBefore(yesterdayStart)) {
        yesterday.add(c);
      } else if (!c.updatedAt.isBefore(weekStart)) {
        thisWeek.add(c);
      } else {
        older.add(c);
      }
    }

    return {
      if (today.isNotEmpty) 'Today': today,
      if (yesterday.isNotEmpty) 'Yesterday': yesterday,
      if (thisWeek.isNotEmpty) 'This Week': thisWeek,
      if (older.isNotEmpty) 'Older': older,
    };
  }

  void _showChatOptions(Chat chat) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                chat.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
              ),
              title: Text(chat.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onTogglePin(chat.id, !chat.isPinned);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await AppFeedback.confirmDelete(
                  context,
                  title: const Text('Delete Chat'),
                  content: Text(
                    'Delete "${chat.name}"? This cannot be undone.',
                  ),
                );
                if (ok) widget.onDeleteChat(chat.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(
    ThemeData theme,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinned = widget.chats.where((c) => c.isPinned).toList();
    final unpinned = widget.chats.where((c) => !c.isPinned).toList();
    final groups = _groupByTime(unpinned);
    final filtered = _filtered;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            if (_isSearching)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _isSearching = false;
                          _query = '';
                        });
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Search chats',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    const AppLogo(size: 26),
                    const SizedBox(width: 10),
                    Text(
                      'RightAnswer',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.menu_open_rounded, size: 20),
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

            // ── Search mode: results ─────────────────────────────────────────
            if (_isSearching) ...[
              Expanded(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _query.isEmpty
                              ? 'Start typing to search…'
                              : 'No chats matching "$_query"',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        children: [
                          for (final chat in filtered)
                            _ChatTile(
                              chat: chat,
                              isSelected: chat.id == widget.currentChatId,
                              onSelect: () => widget.onSelectChat(chat),
                              onLongPress: () => _showChatOptions(chat),
                            ),
                        ],
                      ),
              ),
            ] else ...[
              // ── Action rows ────────────────────────────────────────────────
              _actionRow(
                theme,
                Icons.edit_outlined,
                'New chat',
                widget.onNewChat,
              ),
              _actionRow(
                theme,
                Icons.bolt_rounded,
                'Temporary chat',
                widget.onTempChat,
              ),
              _actionRow(
                theme,
                Icons.search_rounded,
                'Search chats',
                () => setState(() => _isSearching = true),
              ),
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.dividerColor,
              ),
              const SizedBox(height: 4),

              // ── Chat list ──────────────────────────────────────────────────
              Expanded(
                child: widget.chats.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text(
                          'No chats yet',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          // Pinned section
                          if (pinned.isNotEmpty) ...[
                            _sectionLabel(theme, 'PINNED'),
                            for (final chat in pinned)
                              _ChatTile(
                                chat: chat,
                                isSelected: chat.id == widget.currentChatId,
                                onSelect: () => widget.onSelectChat(chat),
                                onLongPress: () => _showChatOptions(chat),
                              ),
                          ],
                          // Recents section
                          if (unpinned.isNotEmpty) ...[
                            _sectionLabel(theme, 'RECENTS'),
                            for (final entry in groups.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  2,
                                ),
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                              for (final chat in entry.value)
                                _ChatTile(
                                  chat: chat,
                                  isSelected: chat.id == widget.currentChatId,
                                  onSelect: () => widget.onSelectChat(chat),
                                  onLongPress: () => _showChatOptions(chat),
                                ),
                            ],
                          ],
                        ],
                      ),
              ),
            ],

            // ── Utility links ─────────────────────────────────────────────
            Divider(height: 1, color: theme.dividerColor),
            _actionRow(
              theme,
              Icons.bookmark_outline,
              'Saved Outputs',
              widget.onSavedOutputs,
            ),
            _actionRow(
              theme,
              Icons.sync_outlined,
              'Generation Queue',
              widget.onQueue,
            ),
            _actionRow(
              theme,
              Icons.settings_outlined,
              'Settings',
              widget.onSettings,
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Chat chat;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onLongPress;

  const _ChatTile({
    required this.chat,
    required this.isSelected,
    required this.onSelect,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onSelect,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (chat.isPinned)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.push_pin_rounded,
                  size: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              )
            else if (chat.isTemporary)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.bolt_rounded,
                  size: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (chat.subjectName != null)
                    Text(
                      chat.subjectName!,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Context Bar ───────────────────────────────────────────────────────────────

/// Passive display of which subject/chapter the AI backend classified this
/// chat under — the client no longer lets the user pick this up front, it's
/// purely informational once the server tells us after an answer.
class _ContextBar extends StatelessWidget {
  final String? subjectName;
  final String? chapterName;

  const _ContextBar({required this.subjectName, required this.chapterName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 15,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              chapterName != null && chapterName!.isNotEmpty
                  ? '$subjectName · $chapterName'
                  : subjectName ?? '',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message Bubble ─────────────────────────────────────────────────────────────
// User: coral pill right-aligned.
// AI: no box — editorial text flowing directly on the canvas, with ✦ mark header.

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;
  final VoidCallback onCopy;
  final VoidCallback onRead;
  final VoidCallback? onRegenerate;
  final VoidCallback? onFullscreen;
  final VoidCallback? onSources;

  const _MessageBubble({
    required this.message,
    this.isStreaming = false,
    required this.onCopy,
    required this.onRead,
    this.onRegenerate,
    this.onFullscreen,
    this.onSources,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = message;
    final isDark = theme.brightness == Brightness.dark;

    if (msg.isUser) {
      return _UserMessage(message: msg, isDark: isDark);
    }
    return _AiMessage(
      message: msg,
      isStreaming: isStreaming,
      isDark: isDark,
      onCopy: onCopy,
      onRead: onRead,
      onFullscreen: onFullscreen,
      onSources: onSources,
    );
  }
}

class _UserMessage extends StatelessWidget {
  final ChatMessage message;
  final bool isDark;
  const _UserMessage({required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const coral = Color(0xFFCC785C);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4, left: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.imagePath != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                width: 200,
                height: 140,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.file(File(message.imagePath!), fit: BoxFit.cover),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: coral,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: SelectableText(
                message.content,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiMessage extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;
  final bool isDark;
  final VoidCallback onCopy;
  final VoidCallback onRead;
  final VoidCallback? onFullscreen;
  final VoidCallback? onSources;

  const _AiMessage({
    required this.message,
    required this.isStreaming,
    required this.isDark,
    required this.onCopy,
    required this.onRead,
    this.onFullscreen,
    this.onSources,
  });

  @override
  Widget build(BuildContext context) {
    const coral = Color(0xFFCC785C);

    final showContent = message.content.trim().isNotEmpty;
    final showActions = showContent && !isStreaming;

    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✦ RightAnswer label
          Row(
            children: [
              Text(
                '✦',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: coral,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'RightAnswer',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: coral,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (message.imagePath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              width: 200,
              height: 140,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.file(File(message.imagePath!), fit: BoxFit.cover),
            ),
          // Editorial AI content — no box, flows on canvas
          if (showContent)
            RichAnswerView(
              content: message.content,
              blocks: message.blocks,
              sources: message.sources,
              isDark: isDark,
            )
          else if (isStreaming)
            _DotsIndicator(color: coral),
          // Action bar
          if (showActions) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AiActionBtn(
                  icon: Icons.copy_outlined,
                  label: 'Copy',
                  onTap: onCopy,
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
                _AiActionBtn(
                  icon: Icons.volume_up_outlined,
                  label: 'Read',
                  onTap: onRead,
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
                _AiActionBtn(
                  icon: Icons.open_in_full_rounded,
                  label: 'Full',
                  onTap: onFullscreen ?? () {},
                  isDark: isDark,
                ),
                if (onSources != null) ...[
                  const SizedBox(width: 6),
                  _AiActionBtn(
                    icon: Icons.menu_book_outlined,
                    label: 'Sources',
                    onTap: onSources!,
                    isDark: isDark,
                    isActive: true,
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 4),
          Divider(
            height: 1,
            color: isDark ? const Color(0xFF2E2C28) : const Color(0xFFEBE6DF),
          ),
        ],
      ),
    );
  }
}

class _AiActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool isActive;

  const _AiActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    const coral = Color(0xFFCC785C);
    final fgColor = isActive
        ? coral
        : isDark
        ? const Color(0xFF8E8B82)
        : const Color(0xFF6C6A64);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated dots ─────────────────────────────────────────────────────────────

class _DotsIndicator extends StatefulWidget {
  final Color color;
  const _DotsIndicator({required this.color});

  @override
  State<_DotsIndicator> createState() => _DotsIndicatorState();
}

class _DotsIndicatorState extends State<_DotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (_ctrl.value - i * 0.25) % 1.0;
          final opacity = phase < 0.5
              ? 0.3 + 0.7 * (phase / 0.5)
              : 1.0 - 0.7 * ((phase - 0.5) / 0.5);
          return Container(
            margin: EdgeInsets.only(left: i > 0 ? 5 : 0),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const coral = Color(0xFFCC785C);
    final mutedColor = isDark
        ? const Color(0xFF8E8B82)
        : const Color(0xFF6C6A64);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '✦',
                  style: GoogleFonts.inter(
                    fontSize: 40,
                    color: coral,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'What would you like\nto learn today?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: -0.3,
                    color: isDark
                        ? const Color(0xFFFAF9F5)
                        : const Color(0xFF141413),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Type a question below to get started',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: mutedColor,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Input Area ────────────────────────────────────────────────────────────────

class _InputArea extends StatelessWidget {
  final TextEditingController inputCtrl;
  final bool isGenerating;
  final bool isRecording;
  final String? selectedImagePath;
  final String? selectedResponseLanguage;
  final String? selectedChapterLabel;
  final VoidCallback onSend;
  final VoidCallback onVoice;
  final VoidCallback onRemoveImage;
  final VoidCallback onClearLanguage;
  final VoidCallback onClearChapter;
  final VoidCallback onOpenPlus;
  final VoidCallback onFullscreen;

  const _InputArea({
    required this.inputCtrl,
    required this.isGenerating,
    required this.isRecording,
    required this.selectedImagePath,
    required this.selectedResponseLanguage,
    this.selectedChapterLabel,
    required this.onSend,
    required this.onVoice,
    required this.onRemoveImage,
    required this.onClearLanguage,
    required this.onClearChapter,
    required this.onOpenPlus,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedImagePath != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(selectedImagePath!),
                          height: 80,
                          width: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: onRemoveImage,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (selectedResponseLanguage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.translate_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Reply in $selectedResponseLanguage',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: onClearLanguage,
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (selectedChapterLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelectedChapterChip(
                    label: selectedChapterLabel!,
                    onClear: onClearChapter,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: ValueListenableBuilder(
                valueListenable: inputCtrl,
                builder: (context, value, child) {
                  final hasText = value.text.isNotEmpty;
                  return Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_rounded),
                          iconSize: 22,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          onPressed: isGenerating ? null : onOpenPlus,
                          tooltip: 'More options',
                        ),
                        Expanded(
                          child: TextField(
                            controller: inputCtrl,
                            maxLines: 5,
                            minLines: 1,
                            enabled: !isGenerating,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: isRecording
                                  ? 'Listening...'
                                  : 'Ask RightAnswer...',
                              filled: false,
                              fillColor: Colors.transparent,
                              hintStyle: TextStyle(
                                color: isRecording
                                    ? Colors.red
                                    : theme.colorScheme.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              isDense: true,
                            ),
                            onSubmitted: isGenerating ? null : (_) => onSend(),
                          ),
                        ),
                        if (hasText)
                          IconButton(
                            icon: const Icon(Icons.open_in_full_rounded),
                            iconSize: 18,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            onPressed: onFullscreen,
                            tooltip: 'Fullscreen',
                          ),
                        if (isGenerating)
                          const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (hasText)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                            child: GestureDetector(
                              onTap: onSend,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          )
                        else
                          IconButton(
                            icon: Icon(
                              isRecording
                                  ? Icons.stop_rounded
                                  : Icons.mic_outlined,
                              color: isRecording
                                  ? Colors.red
                                  : theme.colorScheme.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
                            ),
                            onPressed: onVoice,
                            iconSize: 22,
                            tooltip: isRecording
                                ? 'Stop recording'
                                : 'Voice input',
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plus Menu Sheet ───────────────────────────────────────────────────────────

class _PlusMenuSheet extends StatefulWidget {
  final String responseLength;
  final String reasoningLevel;
  final String selectedResponseLanguage;
  final String? selectedChapterLabel;
  final void Function(String) onLengthChanged;
  final void Function(String) onReasoningChanged;
  final void Function(String) onLanguageChanged;
  final VoidCallback onPickChapter;
  final VoidCallback onClearChapter;
  final VoidCallback onCamera;
  final VoidCallback onPhotos;
  final VoidCallback onFiles;
  final VoidCallback onSolve;
  final VoidCallback onExplain;
  final VoidCallback onChapterSummary;
  final VoidCallback onKeyPoints;
  final VoidCallback onLearningObjectives;

  const _PlusMenuSheet({
    required this.responseLength,
    required this.reasoningLevel,
    required this.selectedResponseLanguage,
    this.selectedChapterLabel,
    required this.onLengthChanged,
    required this.onReasoningChanged,
    required this.onLanguageChanged,
    required this.onPickChapter,
    required this.onClearChapter,
    required this.onCamera,
    required this.onPhotos,
    required this.onFiles,
    required this.onSolve,
    required this.onExplain,
    required this.onChapterSummary,
    required this.onKeyPoints,
    required this.onLearningObjectives,
  });

  @override
  State<_PlusMenuSheet> createState() => _PlusMenuSheetState();
}

class _PlusMenuSheetState extends State<_PlusMenuSheet> {
  String? _expandedPanel;
  late String _reasoningLevel;
  late String _responseLength;
  late String _selectedResponseLanguage;

  @override
  void initState() {
    super.initState();
    _reasoningLevel = widget.reasoningLevel;
    _responseLength = widget.responseLength;
    _selectedResponseLanguage = widget.selectedResponseLanguage;
  }

  double _reasoningToSlider(String v) => v == 'low'
      ? 0
      : v == 'mid'
      ? 1
      : 2;

  String _sliderToReasoning(double v) => v <= 0.5
      ? 'low'
      : v <= 1.5
      ? 'mid'
      : 'high';

  double _lengthToSlider(String v) => v == 'small'
      ? 0
      : v == 'normal'
      ? 1
      : 2;

  String _sliderToLength(double v) => v <= 0.5
      ? 'small'
      : v <= 1.5
      ? 'normal'
      : 'large';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Options',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // Media row
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MediaBtn(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    onTap: widget.onCamera,
                  ),
                  _MediaBtn(
                    icon: Icons.photo_library_outlined,
                    label: 'Photos',
                    onTap: widget.onPhotos,
                  ),
                  _MediaBtn(
                    icon: Icons.attach_file_rounded,
                    label: 'Files',
                    onTap: widget.onFiles,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: theme.dividerColor,
              indent: 16,
              endIndent: 16,
            ),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.menu_book_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              title: const Text(
                'Chapter',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                widget.selectedChapterLabel ?? 'None — searches globally',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              trailing: widget.selectedChapterLabel != null
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: widget.onClearChapter,
                      tooltip: 'Clear chapter',
                    )
                  : const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: widget.onPickChapter,
            ),
            Divider(
              height: 1,
              color: theme.dividerColor,
              indent: 16,
              endIndent: 16,
            ),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.translate_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              title: const Text(
                'Response Language',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _selectedResponseLanguage,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              trailing: const Icon(Icons.expand_more, size: 20),
              onTap: () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => LanguagePickerSheet(
                    title: 'Response Language',
                    languages: appResponseLanguageLabels,
                    selectedLanguage: _selectedResponseLanguage,
                  ),
                );
                if (selected == null) return;
                setState(() => _selectedResponseLanguage = selected);
                widget.onLanguageChanged(selected);
              },
            ),
            Divider(
              height: 1,
              color: theme.dividerColor,
              indent: 16,
              endIndent: 16,
            ),
            // Reasoning row
            ListTile(
              dense: true,
              leading: Icon(
                Icons.psychology_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              title: const Text(
                'Reasoning',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _reasoningLevel[0].toUpperCase() + _reasoningLevel.substring(1),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              trailing: Icon(
                _expandedPanel == 'reasoning'
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 20,
              ),
              onTap: () => setState(
                () => _expandedPanel = _expandedPanel == 'reasoning'
                    ? null
                    : 'reasoning',
              ),
            ),
            if (_expandedPanel == 'reasoning')
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  children: [
                    Slider(
                      value: _reasoningToSlider(_reasoningLevel),
                      min: 0,
                      max: 2,
                      divisions: 2,
                      onChanged: (v) {
                        final newVal = _sliderToReasoning(v);
                        setState(() => _reasoningLevel = newVal);
                        widget.onReasoningChanged(newVal);
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: ['Low', 'Mid', 'High'].map((label) {
                        final active = _reasoningLevel == label.toLowerCase();
                        return Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: active
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            Divider(
              height: 1,
              color: theme.dividerColor,
              indent: 16,
              endIndent: 16,
            ),
            // Length row
            ListTile(
              dense: true,
              leading: Icon(
                Icons.straighten_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              title: const Text(
                'Length',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _responseLength == 'small'
                    ? 'Brief'
                    : _responseLength == 'large'
                    ? 'Detailed'
                    : 'Normal',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              trailing: Icon(
                _expandedPanel == 'length'
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 20,
              ),
              onTap: () => setState(
                () => _expandedPanel = _expandedPanel == 'length'
                    ? null
                    : 'length',
              ),
            ),
            if (_expandedPanel == 'length')
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  children: [
                    Slider(
                      value: _lengthToSlider(_responseLength),
                      min: 0,
                      max: 2,
                      divisions: 2,
                      onChanged: (v) {
                        final newVal = _sliderToLength(v);
                        setState(() => _responseLength = newVal);
                        widget.onLengthChanged(newVal);
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children:
                          [
                            ('Brief', 'small'),
                            ('Normal', 'normal'),
                            ('Detailed', 'large'),
                          ].map((pair) {
                            final active = _responseLength == pair.$2;
                            return Text(
                              pair.$1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: active
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withValues(
                                        alpha: 0.5,
                                      ),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            Divider(
              height: 1,
              color: theme.dividerColor,
              indent: 16,
              endIndent: 16,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'QUICK ACTIONS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _QuickChip(
                      icon: Icons.calculate_outlined,
                      label: 'Solve',
                      onTap: widget.onSolve,
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      icon: Icons.lightbulb_outline,
                      label: 'Explain',
                      onTap: widget.onExplain,
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      icon: Icons.summarize_outlined,
                      label: 'Chapter Summary',
                      onTap: widget.onChapterSummary,
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      icon: Icons.format_list_bulleted_rounded,
                      label: 'Key Points',
                      onTap: widget.onKeyPoints,
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      icon: Icons.track_changes_rounded,
                      label: 'Learning Objectives',
                      onTap: widget.onLearningObjectives,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MediaBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 24,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fullscreen Input Screen ───────────────────────────────────────────────────

class _FullscreenInputScreen extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isGenerating;

  const _FullscreenInputScreen({
    required this.controller,
    required this.onSend,
    required this.isGenerating,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Compose',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_fullscreen_rounded),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Minimize',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            autofocus: true,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Ask RightAnswer...',
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              border: InputBorder.none,
            ),
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isGenerating ? null : onSend,
        backgroundColor: isGenerating
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primary,
        child: isGenerating
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              )
            : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
      ),
    );
  }
}

// ── Fullscreen Response Screen ────────────────────────────────────────────────

class _FullscreenResponseScreen extends StatelessWidget {
  final String content;
  final List<Map<String, dynamic>>? blocks;
  final List<Map<String, dynamic>> sources;
  final VoidCallback onCopy;

  const _FullscreenResponseScreen({
    required this.content,
    this.blocks,
    this.sources = const [],
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Response',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 20),
            tooltip: 'Copy',
            onPressed: () {
              onCopy();
              Navigator.pop(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close_fullscreen_rounded),
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: RichAnswerView(
            content: content,
            blocks: blocks,
            sources: sources,
            isDark: theme.brightness == Brightness.dark,
          ),
        ),
      ),
    );
  }
}

// ── Resources Sheet ───────────────────────────────────────────────────────────

class _ResourcesSheet extends StatelessWidget {
  final List<String> chunks;
  final List<Map<String, dynamic>> sources;

  const _ResourcesSheet({required this.chunks, this.sources = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Prefer the structured `sources` (page/subject/chapter metadata) when
    // the backend provided them; fall back to the plain-text chunks.
    final useStructured = sources.isNotEmpty;
    final itemCount = useStructured ? sources.length : chunks.length;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Source Material',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$itemCount excerpt${itemCount != 1 ? 's' : ''}',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Text(
                'Text passages from your study material used to answer this question.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: itemCount,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final source = useStructured ? sources[i] : null;
                  final text = useStructured
                      ? (source!['text']?.toString() ?? '')
                      : chunks[i];
                  final metaLabel = useStructured
                      ? [
                          source!['subjectName']?.toString(),
                          source['chapterName']?.toString(),
                        ].where((v) => v != null && v.isNotEmpty).join(' · ')
                      : '';
                  final pageLabel = useStructured && source!['pageNumber'] != null
                      ? 'p. ${source['pageNumber']}'
                      : null;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                metaLabel.isNotEmpty
                                    ? metaLabel
                                    : 'Excerpt ${i + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            if (pageLabel != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                pageLabel,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          text,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.55,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.85,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

