import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../recorder/providers/service_providers.dart';

/// Input bar for adding entries to the journal
///
/// Supports text input and voice recording with transcription.
class JournalInputBar extends ConsumerStatefulWidget {
  final Future<void> Function(String text) onTextSubmitted;
  final Future<void> Function(String transcript, String audioPath, int duration)?
      onVoiceRecorded;

  const JournalInputBar({
    super.key,
    required this.onTextSubmitted,
    this.onVoiceRecorded,
  });

  @override
  ConsumerState<JournalInputBar> createState() => _JournalInputBarState();
}

class _JournalInputBarState extends ConsumerState<JournalInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isRecording = false;
  bool _isSubmitting = false;
  bool _isProcessing = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;

  Future<void> _submitText() async {
    if (!_hasText || _isSubmitting) return;

    final text = _controller.text.trim();
    setState(() => _isSubmitting = true);

    try {
      await widget.onTextSubmitted(text);
      _controller.clear();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || widget.onVoiceRecorded == null) return;

    final audioService = ref.read(audioServiceProvider);

    try {
      await audioService.ensureInitialized();
      final started = await audioService.startRecording();

      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not start recording. Check microphone permissions.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording) {
          setState(() {
            _recordingDuration = _recordingDuration + const Duration(seconds: 1);
          });
        }
      });

      debugPrint('[JournalInputBar] Recording started');
    } catch (e) {
      debugPrint('[JournalInputBar] Failed to start recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    _durationTimer?.cancel();
    _durationTimer = null;

    final audioService = ref.read(audioServiceProvider);
    final postProcessingService = ref.read(recordingPostProcessingProvider);

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    try {
      final audioPath = await audioService.stopRecording();

      if (audioPath == null) {
        throw Exception('No audio file saved');
      }

      debugPrint('[JournalInputBar] Recording stopped, transcribing...');

      // Transcribe the recording
      final result = await postProcessingService.process(audioPath: audioPath);
      final transcript = result.transcript;
      final durationSeconds = _recordingDuration.inSeconds;

      debugPrint('[JournalInputBar] Transcription complete: ${transcript.length} chars');

      // Call the callback with transcript and audio path
      if (widget.onVoiceRecorded != null && transcript.isNotEmpty) {
        await widget.onVoiceRecorded!(transcript, audioPath, durationSeconds);
      } else if (transcript.isEmpty) {
        // If transcription is empty, delete the audio file
        try {
          await File(audioPath).delete();
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No speech detected. Recording discarded.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[JournalInputBar] Failed to process recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process recording: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        border: Border(
          top: BorderSide(
            color: isDark ? BrandColors.charcoal : BrandColors.stone,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Recording indicator
            if (_isRecording || _isProcessing) ...[
              _buildRecordingIndicator(isDark),
              const SizedBox(height: 8),
            ],

            // Input row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Voice record button
                _buildVoiceButton(isDark),
                const SizedBox(width: 8),

                // Text input field
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.cream,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? BrandColors.forest
                            : (isDark ? BrandColors.charcoal : BrandColors.stone),
                        width: _focusNode.hasFocus ? 1.5 : 1,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: null,
                      enabled: !_isRecording && !_isProcessing,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? BrandColors.softWhite : BrandColors.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: _isRecording
                            ? 'Recording...'
                            : (_isProcessing ? 'Transcribing...' : 'Capture a thought...'),
                        hintStyle: TextStyle(
                          color: BrandColors.driftwood,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submitText(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send button
                _buildSendButton(isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isProcessing
            ? BrandColors.turquoise.withValues(alpha: 0.1)
            : BrandColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isProcessing) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Transcribing...',
              style: TextStyle(
                color: BrandColors.turquoise,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: BrandColors.error,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(_recordingDuration),
              style: TextStyle(
                color: BrandColors.error,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceButton(bool isDark) {
    final isDisabled = _isProcessing;
    final isActive = _isRecording;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isActive
            ? BrandColors.error
            : (isDisabled
                ? (isDark ? BrandColors.charcoal : BrandColors.stone)
                : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.forestMist)),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: isDisabled ? null : _toggleRecording,
        icon: _isProcessing
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? BrandColors.driftwood : BrandColors.charcoal,
                  ),
                ),
              )
            : Icon(
                isActive ? Icons.stop : Icons.mic,
                color: isActive
                    ? BrandColors.softWhite
                    : (isDisabled ? BrandColors.driftwood : BrandColors.forest),
                size: 22,
              ),
      ),
    );
  }

  Widget _buildSendButton(bool isDark) {
    final canSend = _hasText && !_isSubmitting && !_isRecording && !_isProcessing;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: canSend
            ? BrandColors.forest
            : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: canSend ? _submitText : null,
        icon: _isSubmitting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    BrandColors.softWhite,
                  ),
                ),
              )
            : Icon(
                Icons.arrow_upward,
                color: canSend
                    ? BrandColors.softWhite
                    : BrandColors.driftwood,
                size: 22,
              ),
      ),
    );
  }
}
