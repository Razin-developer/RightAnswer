import 'dart:async';

import 'package:flutter/material.dart';

import '../services/speech_service.dart';

class VoiceInputSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String initialText;
  final String? localeId;
  final String? localeLabel;

  const VoiceInputSheet({
    super.key,
    required this.title,
    required this.initialText,
    this.subtitle,
    this.localeId,
    this.localeLabel,
  });

  @override
  State<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends State<VoiceInputSheet> {
  final _speech = SpeechService.instance;

  Timer? _timer;
  String _transcript = '';
  String? _errorMessage;
  bool _isListening = false;
  Duration _elapsed = Duration.zero;
  double _soundLevel = 0;

  @override
  void initState() {
    super.initState();
    _transcript = widget.initialText;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _speech.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    setState(() {
      _errorMessage = null;
      _soundLevel = 0;
    });
    final started = await _speech.startListening(
      localeId: widget.localeId,
      onResult: (words, _) {
        if (!mounted) return;
        setState(() {
          _transcript = words.trim();
        });
      },
      onStatus: (status) {
        final lowered = status.toLowerCase();
        if (!mounted) return;
        if (lowered.contains('listening')) {
          _startTimer();
          setState(() => _isListening = true);
          return;
        }
        if (lowered.contains('notlistening') || lowered.contains('done')) {
          _stopTimer();
          setState(() => _isListening = false);
        }
      },
      onError: (message) {
        if (!mounted) return;
        _stopTimer();
        setState(() {
          _isListening = false;
          _errorMessage = message;
        });
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        setState(() => _soundLevel = level.clamp(0, 24));
      },
    );

    if (!mounted) return;
    if (started) {
      _startTimer();
      setState(() => _isListening = true);
    } else {
      setState(() {
        _isListening = false;
        _errorMessage = 'Speech recognition is not available on this device.';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      _stopTimer();
      setState(() => _isListening = false);
      return;
    }
    await _startListening();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatElapsed(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pulseScale = 1 + (_soundLevel / 60);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle ??
                              (_isListening
                                  ? 'Listening now${widget.localeLabel == null ? '' : ' in ${widget.localeLabel}'}'
                                  : 'Tap the mic to retry or use the captured text'),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatElapsed(_elapsed),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: AnimatedScale(
                  scale: pulseScale,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isListening
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      boxShadow: _isListening
                          ? [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.24,
                                ),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      _isListening
                          ? Icons.graphic_eq_rounded
                          : Icons.mic_none_rounded,
                      color: _isListening
                          ? Colors.white
                          : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      size: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 140),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Text(
                  _transcript.isEmpty
                      ? 'Start speaking and your words will appear here.'
                      : _transcript,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: _transcript.isEmpty
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _toggleListening,
                      icon: Icon(
                        _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(_isListening ? 'Stop' : 'Retry'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _transcript.trim().isEmpty
                          ? null
                          : () => Navigator.pop(context, _transcript.trim()),
                      child: const Text('Use Text'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
