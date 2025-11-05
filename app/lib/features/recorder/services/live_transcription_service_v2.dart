import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as path;
import 'package:app/features/recorder/services/whisper_local_service.dart';

/// Represents a transcribed segment (paragraph)
class TranscriptionSegment {
  final int index; // Segment number (1, 2, 3, ...)
  final String text;
  final TranscriptionSegmentStatus status;
  final DateTime timestamp;

  TranscriptionSegment({
    required this.index,
    required this.text,
    required this.status,
    required this.timestamp,
  });

  TranscriptionSegment copyWith({
    int? index,
    String? text,
    TranscriptionSegmentStatus? status,
    DateTime? timestamp,
  }) {
    return TranscriptionSegment(
      index: index ?? this.index,
      text: text ?? this.text,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

enum TranscriptionSegmentStatus {
  pending, // Waiting to be transcribed
  processing, // Currently being transcribed
  completed, // Transcription done
  failed, // Transcription error
}

/// Simple service for manual pause-based transcription
///
/// Flow:
/// 1. User starts recording → Records to one continuous audio file
/// 2. User pauses → Transcribes everything recorded so far
/// 3. User resumes → Continues recording to same file
/// 4. Repeat pause/resume for each "paragraph"
/// 5. User stops → Returns complete audio file + all segments
class SimpleTranscriptionService {
  final WhisperLocalService _whisperService;

  // Recording state
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isProcessing = false;

  // File management
  String? _audioFilePath;
  String? _tempDirectory;

  // Segments (paragraphs)
  final List<TranscriptionSegment> _segments = [];
  int _nextSegmentIndex = 1;

  // Progress streaming
  final _segmentStreamController =
      StreamController<TranscriptionSegment>.broadcast();
  final _processingStreamController = StreamController<bool>.broadcast();

  Stream<TranscriptionSegment> get segmentStream =>
      _segmentStreamController.stream;
  Stream<bool> get processingStream => _processingStreamController.stream;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get isProcessing => _isProcessing;
  List<TranscriptionSegment> get segments => List.unmodifiable(_segments);
  String? get audioFilePath => _audioFilePath;

  SimpleTranscriptionService(this._whisperService);

  /// Initialize temp directory
  Future<void> initialize() async {
    _tempDirectory = await _createTempDirectory();
    debugPrint('[SimpleTranscription] Initialized: $_tempDirectory');
  }

  /// Start recording to a single audio file
  Future<bool> startRecording() async {
    if (_isRecording) {
      debugPrint('[SimpleTranscription] Already recording');
      return false;
    }

    try {
      // Check permissions
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('[SimpleTranscription] No recording permission');
        return false;
      }

      // Ensure temp directory exists
      if (_tempDirectory == null) {
        await initialize();
      }

      // Create audio file path (WAV format for Whisper compatibility)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _audioFilePath = path.join(_tempDirectory!, 'recording_$timestamp.wav');

      // Start continuous recording with WAV format
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _audioFilePath!,
      );

      _isRecording = true;
      _isPaused = false;
      _segments.clear();
      _nextSegmentIndex = 1;

      debugPrint('[SimpleTranscription] Recording started: $_audioFilePath');
      return true;
    } catch (e) {
      debugPrint('[SimpleTranscription] Failed to start: $e');
      return false;
    }
  }

  /// Pause recording and transcribe current segment
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;

    try {
      // Pause the recorder
      await _recorder.pause();
      _isPaused = true;

      debugPrint('[SimpleTranscription] Paused, starting transcription...');

      // Process the audio recorded so far (non-blocking)
      _processCurrentAudio();
    } catch (e) {
      debugPrint('[SimpleTranscription] Failed to pause: $e');
    }
  }

  /// Resume recording (continues same file, even if processing)
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    try {
      await _recorder.resume();
      _isPaused = false;

      debugPrint(
        '[SimpleTranscription] Resumed recording (processing may continue in background)',
      );
    } catch (e) {
      debugPrint('[SimpleTranscription] Failed to resume: $e');
    }
  }

  /// Stop recording completely and process final segment
  Future<String?> stopRecording() async {
    if (!_isRecording) return _audioFilePath;

    try {
      // If not paused, we need to do a final transcription
      final needsFinalTranscription = !_isPaused && !_isProcessing;

      // Stop the recorder first
      final finalPath = await _recorder.stop();

      _isRecording = false;
      _isPaused = false;

      // If we need final transcription, do it now
      if (needsFinalTranscription && _audioFilePath != null) {
        debugPrint(
          '[SimpleTranscription] Processing final segment before stopping...',
        );
        await _processCurrentAudio();
      } else {
        // Wait for any ongoing processing to complete
        while (_isProcessing) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      debugPrint('[SimpleTranscription] Stopped: ${_segments.length} segments');
      return finalPath ?? _audioFilePath;
    } catch (e) {
      debugPrint('[SimpleTranscription] Failed to stop: $e');
      return _audioFilePath;
    }
  }

  /// Cancel recording immediately without processing (for discard)
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      // Stop the recorder immediately
      await _recorder.stop();

      _isRecording = false;
      _isPaused = false;
      _isProcessing = false; // Force stop any ongoing processing

      // Clear segments
      _segments.clear();
      _nextSegmentIndex = 1;

      debugPrint('[SimpleTranscription] Recording cancelled (no processing)');
    } catch (e) {
      debugPrint('[SimpleTranscription] Failed to cancel: $e');
    }
  }

  /// Get combined text from all completed segments
  String getCombinedText() {
    return _segments
        .where((s) => s.status == TranscriptionSegmentStatus.completed)
        .map((s) => s.text)
        .join('\n\n');
  }

  /// Clear all data and reset
  void clear() {
    _segments.clear();
    _nextSegmentIndex = 1;
    _audioFilePath = null;
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _recorder.dispose();
    await _segmentStreamController.close();
    await _processingStreamController.close();

    // Clean up temp files
    if (_tempDirectory != null) {
      try {
        final dir = Directory(_tempDirectory!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('[SimpleTranscription] Failed to clean up: $e');
      }
    }
  }

  // Private methods

  /// Process the audio file recorded so far
  Future<void> _processCurrentAudio() async {
    if (_audioFilePath == null || _isProcessing) return;

    _isProcessing = true;
    _processingStreamController.add(true);

    // Create a pending segment
    final segment = TranscriptionSegment(
      index: _nextSegmentIndex,
      text: '',
      status: TranscriptionSegmentStatus.pending,
      timestamp: DateTime.now(),
    );
    _segments.add(segment);
    _segmentStreamController.add(segment);

    try {
      // Update to processing
      final processingSegment = segment.copyWith(
        status: TranscriptionSegmentStatus.processing,
      );
      _segments[_segments.length - 1] = processingSegment;
      _segmentStreamController.add(processingSegment);

      debugPrint(
        '[SimpleTranscription] Transcribing segment $_nextSegmentIndex...',
      );

      // Transcribe the entire audio file
      // Note: This will re-transcribe everything, but Whisper is fast enough
      final fullText = await _whisperService.transcribeAudio(_audioFilePath!);

      // Extract just the new text (after previous segments)
      final previousText = _segments
          .where(
            (s) =>
                s.index < _nextSegmentIndex &&
                s.status == TranscriptionSegmentStatus.completed,
          )
          .map((s) => s.text)
          .join('\n\n');

      String newText = fullText;
      if (previousText.isNotEmpty) {
        // Remove the previous text to get only new content
        if (fullText.startsWith(previousText)) {
          newText = fullText.substring(previousText.length).trim();
        }
      }

      // Update to completed
      final completedSegment = processingSegment.copyWith(
        text: newText,
        status: TranscriptionSegmentStatus.completed,
      );
      _segments[_segments.length - 1] = completedSegment;
      _segmentStreamController.add(completedSegment);

      _nextSegmentIndex++;

      debugPrint(
        '[SimpleTranscription] Segment completed: ${newText.length} chars',
      );
    } catch (e) {
      debugPrint('[SimpleTranscription] Transcription failed: $e');

      // Update to failed
      final failedSegment = segment.copyWith(
        status: TranscriptionSegmentStatus.failed,
      );
      _segments[_segments.length - 1] = failedSegment;
      _segmentStreamController.add(failedSegment);
    } finally {
      _isProcessing = false;
      _processingStreamController.add(false);
    }
  }

  Future<String> _createTempDirectory() async {
    final tempDir = Directory.systemTemp;
    final transcriptDir = Directory(
      path.join(tempDir.path, 'parachute_transcription'),
    );

    if (!await transcriptDir.exists()) {
      await transcriptDir.create(recursive: true);
    }

    return transcriptDir.path;
  }
}

/// Exception thrown by SimpleTranscriptionService
class SimpleTranscriptionException implements Exception {
  final String message;
  SimpleTranscriptionException(this.message);

  @override
  String toString() => 'SimpleTranscriptionException: $message';
}
