import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/services/live_transcription_service_v2.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';
import 'package:path/path.dart' as path;

/// Live journaling recording screen with manual pause-based transcription
///
/// User flow:
/// 1. Tap "Start Recording" → Begin speaking
/// 2. Tap "Pause" when done with a thought → Text appears
/// 3. Tap "Resume" → Continue speaking
/// 4. Repeat pause/resume for each paragraph
/// 5. Tap "Stop & Save" → Save complete recording
class LiveRecordingScreen extends ConsumerStatefulWidget {
  const LiveRecordingScreen({super.key});

  @override
  ConsumerState<LiveRecordingScreen> createState() =>
      _LiveRecordingScreenState();
}

class _LiveRecordingScreenState extends ConsumerState<LiveRecordingScreen> {
  late SimpleTranscriptionService _transcriptionService;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFocusNode = FocusNode();

  // State
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isProcessing = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _startTime;
  int _wordCount = 0;

  // Segments
  final List<TranscriptionSegment> _segments = [];

  @override
  void initState() {
    super.initState();
    // Initialize service asynchronously (non-blocking)
    // This allows the UI to appear immediately
    Future.microtask(() => _initializeService());
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _transcriptionService.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeService() async {
    try {
      final whisperService = ref.read(whisperLocalServiceProvider);
      _transcriptionService = SimpleTranscriptionService(whisperService);
      await _transcriptionService.initialize();

      // Listen to segment updates
      _transcriptionService.segmentStream.listen(_handleSegmentUpdate);

      // Listen to processing state
      _transcriptionService.processingStream.listen((isProcessing) {
        if (mounted) {
          setState(() {
            _isProcessing = isProcessing;
          });
        }
      });

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }

      // Auto-start recording
      await _startRecording();
    } catch (e) {
      debugPrint('[LiveRecordingScreen] Initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize recorder: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _handleSegmentUpdate(TranscriptionSegment segment) {
    if (!mounted) return;

    setState(() {
      // Update or add segment
      final index = _segments.indexWhere((s) => s.index == segment.index);
      if (index != -1) {
        _segments[index] = segment;
      } else {
        _segments.add(segment);
      }

      // Update text controller with all completed segments
      _updateTextController();
    });

    // Auto-scroll when new text appears
    if (segment.status == TranscriptionSegmentStatus.completed) {
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  void _updateTextController() {
    final completedText = _segments
        .where((s) => s.status == TranscriptionSegmentStatus.completed)
        .map((s) => s.text)
        .join('\n\n');

    if (_textController.text != completedText) {
      _textController.text = completedText;
    }

    // Update word count
    _wordCount = completedText.trim().isEmpty
        ? 0
        : completedText.trim().split(RegExp(r'\s+')).length;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _startRecording() async {
    final success = await _transcriptionService.startRecording();
    if (success) {
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _startTime = DateTime.now();
      });
      _startDurationTimer();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start recording. Check permissions.'),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _togglePause() async {
    if (_isPaused) {
      await _transcriptionService.resumeRecording();
      setState(() {
        _isPaused = false;
      });
      _startDurationTimer();
    } else {
      _durationTimer?.cancel();
      await _transcriptionService.pauseRecording();
      setState(() {
        _isPaused = true;
      });
    }
  }

  Future<void> _stopAndSave() async {
    _durationTimer?.cancel();

    setState(() {
      _isRecording = false;
    });

    // Show "Finishing transcription..." feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Finishing transcription and saving...'),
            ],
          ),
          duration: Duration(seconds: 30), // Long duration for processing
        ),
      );
    }

    // Stop recording (this will process any remaining audio and wait for completion)
    final audioPath = await _transcriptionService.stopRecording();

    // Dismiss the processing snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    // Save recording
    await _saveRecording(audioPath);
  }

  Future<void> _saveRecording(String? audioPath) async {
    try {
      // Get file system service
      final fileSystem = ref.read(fileSystemServiceProvider);

      // Generate timestamp and filenames
      final now = DateTime.now();
      final timestamp = FileSystemService.formatTimestampForFilename(now);

      final fullTranscript = _transcriptionService.getCombinedText();

      // Get captures folder path
      final capturesPath = await fileSystem.getCapturesPath();

      // Create markdown file
      final markdownPath = path.join(capturesPath, '$timestamp.md');
      final markdownFile = File(markdownPath);

      // Create metadata section
      final metadata = StringBuffer();
      metadata.writeln('---');
      metadata.writeln('created: ${now.toIso8601String()}');
      metadata.writeln('duration: $_formattedDuration');
      metadata.writeln('words: $_wordCount');
      metadata.writeln('source: live_recording');
      metadata.writeln('---');
      metadata.writeln();

      // Write markdown file
      await markdownFile.writeAsString('${metadata.toString()}$fullTranscript');

      // Copy audio file to captures folder if it exists
      if (audioPath != null && await File(audioPath).exists()) {
        final audioDestPath = path.join(capturesPath, '$timestamp.wav');
        await File(audioPath).copy(audioDestPath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording saved!\n$timestamp\n$_wordCount words'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );

        // Go back to home screen
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !_isRecording || _isPaused) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_startTime != null) {
          _recordingDuration = DateTime.now().difference(_startTime!);
        }
      });
    });
  }

  String get _formattedDuration {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while initializing
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Initializing...'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparing recorder...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () async {
          if (_isRecording) {
            final shouldExit = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard Recording?'),
                content: const Text(
                  'Are you sure you want to discard this recording?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            );

            if (shouldExit == true) {
              // Cancel immediately without processing
              await _transcriptionService.cancelRecording();
              if (mounted) {
                Navigator.of(context).pop();
              }
            }
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
      title: _buildSyncStatusIndicator(),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildSyncStatusIndicator() {
    // Placeholder for Git sync status
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_done, size: 16, color: Colors.green),
        const SizedBox(width: 4),
        Text('Synced', style: TextStyle(fontSize: 14, color: Colors.green)),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Prominent status banner at top
        if (_isRecording || _isProcessing) _buildStatusBanner(),

        // Text editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                // Add subtle border when recording
                border: _isRecording
                    ? Border.all(
                        color: _isPaused
                            ? Colors.orange.withValues(alpha: 0.5)
                            : Colors.red.withValues(alpha: 0.5),
                        width: 2,
                      )
                    : null,
              ),
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _textController,
                focusNode: _textFocusNode,
                maxLines: null,
                expands: true,
                scrollController: _scrollController,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: _isRecording
                      ? 'Speak, then pause to see your words...'
                      : 'Tap "Start Recording" to begin...',
                  hintStyle: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ),
        ),

        // Instruction text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildInstructionText(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildInstructionText() {
    if (!_isRecording) {
      return Text(
        'Ready to record',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        textAlign: TextAlign.center,
      );
    } else if (_isPaused) {
      return Text(
        _isProcessing
            ? 'Processing your words...'
            : 'Tap Resume to continue or Edit to modify text',
        style: TextStyle(
          color: _isProcessing ? Colors.orange : Colors.blue,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      );
    } else {
      return Text(
        'Speak your thoughts, then tap Pause',
        style: TextStyle(
          color: Colors.red.shade700,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      );
    }
  }

  Widget _buildStatusBanner() {
    final Color backgroundColor;
    final Color foregroundColor;
    final IconData icon;
    final String message;
    final String detail;

    if (_isProcessing) {
      backgroundColor = Colors.orange;
      foregroundColor = Colors.white;
      icon = Icons.sync;
      message = 'Processing transcription';
      detail = 'Please wait...';
    } else if (_isPaused) {
      backgroundColor = Colors.orange.shade700;
      foregroundColor = Colors.white;
      icon = Icons.pause_circle_filled;
      message = 'Recording paused';
      detail = 'Press Resume to continue';
    } else if (_isRecording) {
      backgroundColor = Colors.red;
      foregroundColor = Colors.white;
      icon = Icons.fiber_manual_record;
      message = 'Recording';
      detail = _formattedDuration;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Animated icon
          if (_isProcessing)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
              ),
            )
          else if (_isRecording && !_isPaused)
            _buildPulsingDot(foregroundColor)
          else
            Icon(icon, color: foregroundColor, size: 24),

          const SizedBox(width: 12),

          // Status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    color: foregroundColor.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Word count badge
          if (_wordCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: foregroundColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_wordCount words',
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPulsingDot(Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      builder: (context, value, child) {
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 8 * value,
                spreadRadius: 4 * value,
              ),
            ],
          ),
        );
      },
      onEnd: () {
        if (mounted && _isRecording && !_isPaused) {
          setState(() {});
        }
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: _isRecording ? _buildRecordingControls() : _buildIdleControls(),
      ),
    );
  }

  Widget _buildIdleControls() {
    return ElevatedButton.icon(
      onPressed: _startRecording,
      icon: const Icon(Icons.mic, size: 28),
      label: const Text(
        'Start Recording',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Row(
      children: [
        // Pause/Resume button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed:
                _togglePause, // Always enabled - can resume during processing
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 24),
            label: Text(
              _isPaused ? 'Resume' : 'Pause',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isPaused
                  ? Colors.green
                  : Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Stop & Save button (prominent, single action)
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            onPressed: _stopAndSave, // Single action to finish
            icon: const Icon(Icons.check_circle, size: 28),
            label: const Text(
              'Stop & Save',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Keyboard/Edit button
        IconButton(
          icon: const Icon(Icons.edit),
          iconSize: 28,
          color: Theme.of(context).colorScheme.primary,
          onPressed: () {
            _textFocusNode.requestFocus();
          },
          tooltip: 'Edit text',
        ),
      ],
    );
  }
}
