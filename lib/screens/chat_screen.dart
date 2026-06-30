import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_languages.dart';
import '../models/chat.dart';
import '../models/chat_message.dart';
import '../models/subject.dart';
import '../models/chapter.dart';
import '../repositories/chat_message_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/subject_repository.dart';
import '../services/chat_ai_service.dart';
import '../services/connectivity_service.dart';
import '../services/tts_service.dart';
import '../models/app_exception.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_logo.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/voice_input_sheet.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

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

  String? _selectedImagePath;
  String? _selectedResponseLanguage;
  String? _streamingMessageId;
  String _responseLength = 'normal';
  String _reasoningLevel = 'mid';
  String? _contextSubjectId;
  String? _contextSubjectName;
  List<String> _contextChapterIds = [];
  List<String> _contextChapterNames = [];

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
    if (mounted) setState(() => _allChats = chats);
  }

  Future<void> _loadChat(Chat chat) async {
    final messages = await _messageRepo.getByChatId(chat.id);
    if (!mounted) return;
    setState(() {
      _currentChat = chat;
      _messages = messages;
      _isTemporary = chat.isTemporary;
      _contextSubjectId = chat.subjectId;
      _contextSubjectName = chat.subjectName;
      _contextChapterIds = List.from(chat.chapterIds);
      _contextChapterNames = List.from(chat.chapterNames);
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
      _contextSubjectId = null;
      _contextSubjectName = null;
      _contextChapterIds = [];
      _contextChapterNames = [];
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
        subjectId: _contextSubjectId,
        subjectName: _contextSubjectName,
        chapterIds: _contextChapterIds,
        chapterNames: _contextChapterNames,
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

    try {
      await for (final event in ChatAIService.instance.streamMessage(
        userContent: text,
        imagePath: imagePathCopy,
        responseLength: _responseLength,
        reasoningLevel: _reasoningLevel,
        responseLanguage: chosenLanguage,
        subjectName: _contextSubjectName,
        chapterIds: _contextChapterIds,
        history: historyBeforeSend,
      )) {
        if (!mounted) return;
        setState(() {
          _messages = _messages
              .map(
                (message) => message.id == assistantMsg.id
                    ? message.copyWith(
                        content: event.content,
                        tokenCount: event.inputTokens + event.outputTokens,
                        cost: event.cost,
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
        subjectName: _contextSubjectName,
        chapterIds: _contextChapterIds,
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
    final name = await ChatAIService.instance.generateChatName(firstMessage);
    if (!mounted) return;
    await _chatRepo.updateName(chatId, name);
    setState(
      () => _currentChat = _currentChat?.copyWith(
        name: name,
        updatedAt: DateTime.now(),
      ),
    );
    await _loadAllChats();
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

  Future<void> _renameChat() async {
    if (_currentChat == null) return;
    final ctrl = TextEditingController(text: _currentChat!.name);
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
    if (name == null || name.isEmpty) return;
    await _chatRepo.updateName(_currentChat!.id, name);
    setState(() => _currentChat = _currentChat!.copyWith(name: name));
    await _loadAllChats();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked != null && mounted)
        setState(() => _selectedImagePath = picked.path);
    } catch (e) {
      if (mounted)
        AppFeedback.showToast(
          context,
          'Could not access image: ${e.toString()}',
        );
    }
  }

  Future<void> _toggleVoice() async => _openVoiceComposer();

  Future<void> _openContextSelector() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContextSelectorSheet(
        initialSubjectId: _contextSubjectId,
        initialChapterIds: _contextChapterIds,
        onSelected: (sId, sName, cIds, cNames) {
          setState(() {
            _contextSubjectId = sId;
            _contextSubjectName = sName;
            _contextChapterIds = cIds;
            _contextChapterNames = cNames;
          });
        },
      ),
    );
  }

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
        onLengthChanged: (v) => setState(() => _responseLength = v),
        onReasoningChanged: (v) => setState(() => _reasoningLevel = v),
        onLanguageChanged: (value) {
          setState(() {
            _selectedResponseLanguage = value == autoResponseLanguageLabel
                ? null
                : value;
          });
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
          _ContextBar(
            subjectName: _contextSubjectName,
            chapterNames: _contextChapterNames,
            onTap: _openContextSelector,
            onClear: () => setState(() {
              _contextSubjectId = null;
              _contextSubjectName = null;
              _contextChapterIds = [];
              _contextChapterNames = [];
            }),
          ),
          Expanded(
            child: _messages.isEmpty && !_isGenerating
                ? _EmptyState(
                    hasContext: _contextSubjectName != null,
                    onSelectContext: _openContextSelector,
                  )
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
            onSend: _sendMessage,
            onVoice: _toggleVoice,
            onRemoveImage: () => setState(() => _selectedImagePath = null),
            onClearLanguage: () =>
                setState(() => _selectedResponseLanguage = null),
            onOpenPlus: _openPlusMenu,
            onFullscreen: _openFullscreen,
          ),
        ],
      ),
    );
  }
}

// ── Chat Drawer ───────────────────────────────────────────────────────────────

class _ChatDrawer extends StatelessWidget {
  final List<Chat> chats;
  final String? currentChatId;
  final void Function(Chat) onSelectChat;
  final VoidCallback onNewChat;
  final VoidCallback onTempChat;
  final void Function(String) onDeleteChat;
  final VoidCallback onSettings;

  const _ChatDrawer({
    required this.chats,
    required this.currentChatId,
    required this.onSelectChat,
    required this.onNewChat,
    required this.onTempChat,
    required this.onDeleteChat,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Map<String, List<Chat>> grouped = {};
    for (final c in chats) {
      final key = c.subjectName ?? 'Other';
      grouped.putIfAbsent(key, () => []).add(c);
    }
    final groups = grouped.entries.toList()
      ..sort(
        (a, b) => a.key == 'Other'
            ? 1
            : b.key == 'Other'
            ? -1
            : a.key.compareTo(b.key),
      );

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                children: [
                  const AppLogo(size: 32),
                  const SizedBox(width: 10),
                  Text(
                    'RightAnswer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _DrawerBtn(
                    icon: Icons.add_comment_outlined,
                    label: 'New Chat',
                    onTap: onNewChat,
                  ),
                  const SizedBox(height: 6),
                  _DrawerBtn(
                    icon: Icons.bolt_rounded,
                    label: 'Temporary Chat',
                    isSecondary: true,
                    onTap: onTempChat,
                  ),
                ],
              ),
            ),
            Divider(
              height: 24,
              indent: 12,
              endIndent: 12,
              color: theme.dividerColor,
            ),
            Expanded(
              child: chats.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: groups.length,
                      itemBuilder: (ctx, gi) {
                        final group = groups[gi];
                        return _ChatGroup(
                          label: group.key,
                          chats: group.value,
                          currentChatId: currentChatId,
                          onSelect: onSelectChat,
                          onDelete: onDeleteChat,
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.settings_outlined,
                size: 20,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              title: const Text('Settings', style: TextStyle(fontSize: 13)),
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSecondary;
  final VoidCallback onTap;

  const _DrawerBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSecondary
        ? theme.colorScheme.onSurface.withValues(alpha: 0.65)
        : theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSecondary
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSecondary
                ? theme.dividerColor
                : theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatGroup extends StatelessWidget {
  final String label;
  final List<Chat> chats;
  final String? currentChatId;
  final void Function(Chat) onSelect;
  final void Function(String) onDelete;

  const _ChatGroup({
    required this.label,
    required this.chats,
    required this.currentChatId,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        ...chats.map(
          (chat) => _ChatTile(
            chat: chat,
            isSelected: chat.id == currentChatId,
            onSelect: () => onSelect(chat),
            onDelete: () => onDelete(chat.id),
          ),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Chat chat;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _ChatTile({
    required this.chat,
    required this.isSelected,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onSelect,
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
            Expanded(
              child: Text(
                chat.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Chat'),
                    content: Text(
                      'Delete "${chat.name}"? This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) onDelete();
              },
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Context Bar ───────────────────────────────────────────────────────────────

class _ContextBar extends StatelessWidget {
  final String? subjectName;
  final List<String> chapterNames;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _ContextBar({
    required this.subjectName,
    required this.chapterNames,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasContext = subjectName != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: hasContext
              ? theme.colorScheme.primary.withValues(alpha: 0.07)
              : theme.colorScheme.surfaceContainerLowest,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 16,
              color: hasContext
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: hasContext
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subjectName!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (chapterNames.isNotEmpty)
                          Text(
                            chapterNames.join(', '),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    )
                  : Text(
                      'Select subject & chapters for context',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
            ),
            if (hasContext)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
              )
            else
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;
  final VoidCallback onCopy;
  final VoidCallback onRead;
  final VoidCallback? onRegenerate;

  const _MessageBubble({
    required this.message,
    this.isStreaming = false,
    required this.onCopy,
    required this.onRead,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = message;
    final isUser = msg.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 6,
          bottom: 2,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (msg.imagePath != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                width: 200,
                height: 140,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.file(File(msg.imagePath!), fit: BoxFit.cover),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: isUser
                  ? SelectableText(
                      msg.content,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        height: 1.45,
                      ),
                    )
                  : isStreaming && msg.content.trim().isEmpty
                  ? const _TypingIndicator(inline: true)
                  : MarkdownBody(
                      data: msg.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: const TextStyle(fontSize: 14, height: 1.55),
                        code: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          backgroundColor:
                              theme.colorScheme.surfaceContainerLowest,
                        ),
                      ),
                    ),
            ),
            if (!isUser && msg.content.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionBtn(
                    icon: Icons.copy_outlined,
                    label: 'Copy',
                    onTap: onCopy,
                  ),
                  const SizedBox(width: 4),
                  _ActionBtn(
                    icon: Icons.volume_up_outlined,
                    label: 'Read',
                    onTap: onRead,
                  ),
                  if (onRegenerate != null) ...[
                    const SizedBox(width: 4),
                    _ActionBtn(
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                      onTap: onRegenerate!,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
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

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final bool inline;

  const _TypingIndicator({this.inline = false});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
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
    final theme = Theme.of(context);
    final dots = AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i * 0.33;
          final opacity = ((_ctrl.value - delay).abs() < 0.33) ? 1.0 : 0.3;
          return Container(
            margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
    if (widget.inline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: dots,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: dots,
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasContext;
  final VoidCallback onSelectContext;

  const _EmptyState({required this.hasContext, required this.onSelectContext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Start a Conversation',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasContext
                      ? 'Type a question below to get started'
                      : 'Select a subject and chapters for context-aware answers, or just ask anything',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    height: 1.5,
                  ),
                ),
                if (!hasContext) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onSelectContext,
                    icon: const Icon(Icons.menu_book_outlined, size: 16),
                    label: const Text('Select Study Context'),
                  ),
                ],
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
  final VoidCallback onSend;
  final VoidCallback onVoice;
  final VoidCallback onRemoveImage;
  final VoidCallback onClearLanguage;
  final VoidCallback onOpenPlus;
  final VoidCallback onFullscreen;

  const _InputArea({
    required this.inputCtrl,
    required this.isGenerating,
    required this.isRecording,
    required this.selectedImagePath,
    required this.selectedResponseLanguage,
    required this.onSend,
    required this.onVoice,
    required this.onRemoveImage,
    required this.onClearLanguage,
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
  final void Function(String) onLengthChanged;
  final void Function(String) onReasoningChanged;
  final void Function(String) onLanguageChanged;
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
    required this.onLengthChanged,
    required this.onReasoningChanged,
    required this.onLanguageChanged,
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
                _responseLength[0].toUpperCase() + _responseLength.substring(1),
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
                            ('Small', 'small'),
                            ('Normal', 'normal'),
                            ('Large', 'large'),
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

// ── Context Selector Sheet ────────────────────────────────────────────────────

class _ContextSelectorSheet extends StatefulWidget {
  final String? initialSubjectId;
  final List<String> initialChapterIds;
  final void Function(
    String? subjectId,
    String? subjectName,
    List<String> chapterIds,
    List<String> chapterNames,
  )
  onSelected;

  const _ContextSelectorSheet({
    required this.initialSubjectId,
    required this.initialChapterIds,
    required this.onSelected,
  });

  @override
  State<_ContextSelectorSheet> createState() => _ContextSelectorSheetState();
}

class _ContextSelectorSheetState extends State<_ContextSelectorSheet> {
  final _subjectRepo = SubjectRepository();
  final _chapterRepo = ChapterRepository();
  final _searchCtrl = TextEditingController();

  List<Subject> _subjects = [];
  Map<String, List<Chapter>> _chapters = {};
  final Set<String> _expanded = {};

  String? _selectedSubjectId;
  String? _selectedSubjectName;
  Set<String> _selectedChapterIds = {};
  final Map<String, String> _chapterNames = {};

  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedSubjectId = widget.initialSubjectId;
    _selectedChapterIds = widget.initialChapterIds.toSet();
    if (widget.initialSubjectId != null)
      _expanded.add(widget.initialSubjectId!);
    _load();
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final subjects = await _subjectRepo.getAll();
    final chapters = <String, List<Chapter>>{};
    for (final s in subjects) {
      final chs = await _chapterRepo.getBySubject(s.id);
      chapters[s.id] = chs;
      for (final c in chs) {
        _chapterNames[c.id] = c.title;
      }
    }
    if (_selectedSubjectId != null) {
      final s = subjects.where((x) => x.id == _selectedSubjectId).firstOrNull;
      _selectedSubjectName = s?.name;
    }
    if (mounted) {
      setState(() {
        _subjects = subjects;
        _chapters = chapters;
        _loading = false;
      });
    }
  }

  List<Subject> get _filteredSubjects {
    if (_query.isEmpty) return _subjects;
    return _subjects.where((s) {
      if (s.name.toLowerCase().contains(_query)) return true;
      final chs = _chapters[s.id] ?? [];
      return chs.any(
        (c) =>
            c.title.toLowerCase().contains(_query) ||
            c.className.toLowerCase().contains(_query),
      );
    }).toList();
  }

  List<Chapter> _filteredChapters(String subjectId) {
    final chs = _chapters[subjectId] ?? [];
    if (_query.isEmpty) return chs;
    return chs
        .where(
          (c) =>
              c.title.toLowerCase().contains(_query) ||
              c.className.toLowerCase().contains(_query),
        )
        .toList();
  }

  void _toggleSubject(Subject s) {
    setState(() {
      if (_expanded.contains(s.id)) {
        _expanded.remove(s.id);
      } else {
        _expanded.add(s.id);
      }
    });
  }

  void _selectAllInSubject(Subject s, bool select) {
    final chs = _chapters[s.id] ?? [];
    setState(() {
      _selectedSubjectId = select ? s.id : null;
      _selectedSubjectName = select ? s.name : null;
      if (select) {
        _selectedChapterIds = chs.map((c) => c.id).toSet();
      } else {
        _selectedChapterIds = {};
      }
    });
  }

  void _toggleChapter(Subject s, Chapter ch) {
    setState(() {
      if (_selectedChapterIds.contains(ch.id)) {
        _selectedChapterIds.remove(ch.id);
        if (_selectedChapterIds.isEmpty) {
          _selectedSubjectId = null;
          _selectedSubjectName = null;
        }
      } else {
        _selectedSubjectId = s.id;
        _selectedSubjectName = s.name;
        _selectedChapterIds.add(ch.id);
      }
    });
  }

  void _confirm() {
    final names = _selectedChapterIds
        .map((id) => _chapterNames[id] ?? id)
        .toList();
    widget.onSelected(
      _selectedSubjectId,
      _selectedSubjectName,
      _selectedChapterIds.toList(),
      names,
    );
    Navigator.pop(context);
  }

  void _clear() {
    setState(() {
      _selectedSubjectId = null;
      _selectedSubjectName = null;
      _selectedChapterIds = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredSubjects;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Select Context',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedSubjectId != null)
                    TextButton(
                      onPressed: _clear,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search subjects, chapters...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  isDense: true,
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _subjects.isEmpty
                            ? 'No subjects yet. Add one in the Subjects tab.'
                            : 'No results for "$_query"',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final s = filtered[i];
                        final chs = _filteredChapters(s.id);
                        final allSelected =
                            chs.isNotEmpty &&
                            chs.every(
                              (c) => _selectedChapterIds.contains(c.id),
                            );
                        final someSelected = chs.any(
                          (c) => _selectedChapterIds.contains(c.id),
                        );
                        final isExpanded = _expanded.contains(s.id);

                        return Column(
                          children: [
                            ListTile(
                              dense: true,
                              leading: Checkbox(
                                value: allSelected
                                    ? true
                                    : someSelected
                                    ? null
                                    : false,
                                tristate: true,
                                onChanged: (v) =>
                                    _selectAllInSubject(s, v != false),
                              ),
                              title: Text(
                                s.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                '${chs.length} chapter${chs.length != 1 ? 's' : ''}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  isExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 20,
                                ),
                                onPressed: () => _toggleSubject(s),
                              ),
                              onTap: () => _toggleSubject(s),
                            ),
                            if (isExpanded)
                              ...chs.map(
                                (ch) => CheckboxListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.only(
                                    left: 40,
                                    right: 16,
                                  ),
                                  value: _selectedChapterIds.contains(ch.id),
                                  onChanged: (_) => _toggleChapter(s, ch),
                                  title: Text(
                                    ch.title,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    ch.className,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            Divider(height: 1, color: theme.dividerColor),
                          ],
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  if (_selectedSubjectId != null)
                    Expanded(
                      child: Text(
                        '${_selectedChapterIds.length} chapter${_selectedChapterIds.length != 1 ? 's' : ''} selected',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _confirm,
                    child: const Text('Confirm'),
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
