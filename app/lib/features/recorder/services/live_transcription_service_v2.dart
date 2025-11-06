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
  String? _audioFilePath; // Final merged audio file
  String? _tempDirectory;
  final List<String> _segmentAudioFiles = []; // Individual segment recordings
  String? _currentSegmentFile; // Current segment being recorded

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

      // Set final audio file path (will be created at the end by merging segments)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _audioFilePath = path.join(_tempDirectory!, 'recording_$timestamp.wav');

      // Create first segment file
      _currentSegmentFile = path.join(
        _tempDirectory!,
        'segment_${_nextSegmentIndex}_$timestamp.wav',
      );

      // Start recording first segment
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentSegmentFile!,
      );

      _isRecording = true;
      _isPaused = false;
      _segments.clear();
      _nextSegmentIndex = 1;
      _segmentAudioFiles.clear();

      debugPrint(
        '[SimpleTranscription] Recording started: $_currentSegmentFile',
      );
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
      // Stop current segment
      final segmentPath = await _recorder.stop();
      _isPaused = true;

      debugPrint('[SimpleTranscription] Paused, segment saved: $segmentPath');

      // Save segment file
      if (_currentSegmentFile != null) {
        _segmentAudioFiles.add(_currentSegmentFile!);
      }

      // Process this segment only (non-blocking)
      _processCurrentSegment(_currentSegmentFile!);
    } catch (e) {
      debugPrint('[SimpleTranscription] Failed to pause: $e');
    }
  }

  /// Resume recording (starts new segment file)
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    try {
      // Create new segment file
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentSegmentFile = path.join(
        _tempDirectory!,
        'segment_${_nextSegmentIndex}_$timestamp.wav',
      );

      // Start recording new segment
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentSegmentFile!,
      );

      _isPaused = false;

      debugPrint(
        '[SimpleTranscription] Resumed, new segment: $_currentSegmentFile',
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
      await _recorder.stop();

      _isRecording = false;
      _isPaused = false;

      // If we need final transcription, process the last segment
      if (needsFinalTranscription && _currentSegmentFile != null) {
        debugPrint(
          '[SimpleTranscription] Processing final segment before stopping...',
        );
        _segmentAudioFiles.add(_currentSegmentFile!);
        await _processCurrentSegment(_currentSegmentFile!);
      } else {
        // Wait for any ongoing processing to complete
        while (_isProcessing) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      // Merge all segment files into final audio file
      if (_segmentAudioFiles.isNotEmpty && _audioFilePath != null) {
        debugPrint(
          '[SimpleTranscription] Merging ${_segmentAudioFiles.length} segments...',
        );
        await _mergeAudioSegments(_segmentAudioFiles, _audioFilePath!);
        debugPrint(
          '[SimpleTranscription] Segments merged into: $_audioFilePath',
        );
      }

      debugPrint('[SimpleTranscription] Stopped: ${_segments.length} segments');
      return _audioFilePath;
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
  Future<void> _processCurrentSegment(String segmentFilePath) async {
    if (_isProcessing) return;

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
        '[SimpleTranscription] Transcribing segment $_nextSegmentIndex from $segmentFilePath...',
      );

      // Transcribe ONLY this segment file
      final segmentText = await _whisperService.transcribeAudio(
        segmentFilePath,
      );

      debugPrint(
        '[SimpleTranscription] Segment transcribed: ${segmentText.length} chars',
      );

      // Update to completed
      final completedSegment = processingSegment.copyWith(
        text: segmentText.trim(),
        status: TranscriptionSegmentStatus.completed,
      );
      _segments[_segments.length - 1] = completedSegment;
      _segmentStreamController.add(completedSegment);

      _nextSegmentIndex++;

      debugPrint('[SimpleTranscription] Segment completed successfully');
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

  /// Merge multiple WAV segment files into a single WAV file
  Future<void> _mergeAudioSegments(
    List<String> segmentPaths,
    String outputPath,
  ) async {
    try {
      if (segmentPaths.isEmpty) return;

      // If only one segment, just copy it
      if (segmentPaths.length == 1) {
        final sourceFile = File(segmentPaths.first);
        await sourceFile.copy(outputPath);
        return;
      }

      // For multiple segments, we need to concatenate the audio data
      // WAV file structure: RIFF header (44 bytes) + audio data
      final outputFile = File(outputPath);
      final sink = outputFile.openWrite();

      try {
        int totalDataSize = 0;
        final List<List<int>> audioDataChunks = [];

        // Read all segment files and extract audio data
        for (final segmentPath in segmentPaths) {
          final file = File(segmentPath);
          final bytes = await file.readAsBytes();

          // Skip WAV header (44 bytes) and get audio data
          if (bytes.length > 44) {
            final audioData = bytes.sublist(44);
            audioDataChunks.add(audioData);
            totalDataSize += audioData.length;
          }
        }

        // Write WAV header from first file (assumes all segments have same format)
        final firstFile = File(segmentPaths.first);
        final firstBytes = await firstFile.readAsBytes();
        final header = firstBytes.sublist(0, 44);

        // Update the file size in the header
        final totalFileSize = 36 + totalDataSize;
        header[4] = totalFileSize & 0xFF;
        header[5] = (totalFileSize >> 8) & 0xFF;
        header[6] = (totalFileSize >> 16) & 0xFF;
        header[7] = (totalFileSize >> 24) & 0xFF;

        // Update data chunk size
        header[40] = totalDataSize & 0xFF;
        header[41] = (totalDataSize >> 8) & 0xFF;
        header[42] = (totalDataSize >> 16) & 0xFF;
        header[43] = (totalDataSize >> 24) & 0xFF;

        // Write header
        sink.add(header);

        // Write all audio data chunks
        for (final audioData in audioDataChunks) {
          sink.add(audioData);
        }

        await sink.flush();
      } finally {
        await sink.close();
      }

      debugPrint(
        '[SimpleTranscription] Merged ${segmentPaths.length} segments into $outputPath',
      );
    } catch (e) {
      debugPrint('[SimpleTranscription] Error merging audio segments: $e');
      rethrow;
    }
  }
}

/// Exception thrown by SimpleTranscriptionService
class SimpleTranscriptionException implements Exception {
  final String message;
  SimpleTranscriptionException(this.message);

  @override
  String toString() => 'SimpleTranscriptionException: $message';
}
