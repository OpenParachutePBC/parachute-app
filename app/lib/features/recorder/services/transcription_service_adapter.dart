import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app/services/parakeet_service.dart';
import 'package:app/features/recorder/services/whisper_local_service.dart';
import 'package:app/features/recorder/models/whisper_models.dart'
    show WhisperModelType, TranscriptionProgress;

/// Platform-adaptive transcription service
///
/// Uses Parakeet (FluidAudio) on iOS/macOS for fast, high-quality transcription
/// Falls back to Whisper on Android and other platforms
///
/// This is a drop-in replacement for WhisperLocalService with the same interface.
class TranscriptionServiceAdapter {
  final ParakeetService _parakeetService = ParakeetService();
  final WhisperLocalService? _whisperService;

  // Progress tracking
  final _transcriptionProgressController =
      StreamController<TranscriptionProgress>.broadcast();

  Stream<TranscriptionProgress> get transcriptionProgressStream =>
      _transcriptionProgressController.stream;

  bool get isUsingParakeet => _parakeetService.isSupported;
  String get engineName => isUsingParakeet ? 'Parakeet v3' : 'Whisper';

  TranscriptionServiceAdapter({WhisperLocalService? whisperService})
    : _whisperService = whisperService;

  /// Initialize the transcription service
  ///
  /// For iOS/macOS: Initializes Parakeet (downloads models if needed)
  /// For Android: Ensures Whisper model is downloaded
  Future<void> initialize() async {
    if (_parakeetService.isSupported) {
      // iOS/macOS: Initialize Parakeet
      debugPrint('[TranscriptionAdapter] Initializing Parakeet...');
      try {
        await _parakeetService.initialize(version: 'v3');
        debugPrint('[TranscriptionAdapter] ✅ Parakeet ready');
      } catch (e) {
        debugPrint('[TranscriptionAdapter] ⚠️ Parakeet init failed: $e');
        throw TranscriptionException(
          'Failed to initialize Parakeet: ${e.toString()}',
        );
      }
    } else {
      // Android: Check Whisper is ready
      debugPrint('[TranscriptionAdapter] Using Whisper on Android');
      if (_whisperService == null) {
        throw TranscriptionException(
          'Whisper service not available for Android platform',
        );
      }

      final isReady = await _whisperService!.isReady();
      if (!isReady) {
        throw TranscriptionException(
          'Whisper not ready. Please download a model in Settings.',
        );
      }
    }
  }

  /// Transcribe audio file
  ///
  /// [audioPath] - Absolute path to audio file (WAV, 16kHz mono)
  /// [modelType] - Only used for Whisper (Android). Ignored on iOS/macOS.
  /// [language] - Optional language hint. Parakeet auto-detects, Whisper uses this.
  /// [onProgress] - Progress callback
  ///
  /// Returns transcribed text
  Future<String> transcribeAudio(
    String audioPath, {
    WhisperModelType? modelType,
    String? language,
    Function(TranscriptionProgress)? onProgress,
  }) async {
    // Lazy initialization - initialize on first use if not already done
    if (_parakeetService.isSupported && !_parakeetService.isInitialized) {
      debugPrint('[TranscriptionAdapter] Lazy-initializing Parakeet...');
      try {
        await initialize();
      } catch (e) {
        debugPrint(
          '[TranscriptionAdapter] ⚠️ Lazy init failed, falling back to Whisper: $e',
        );
        // Fall through to Whisper if initialization fails
      }
    }

    if (_parakeetService.isSupported && _parakeetService.isInitialized) {
      return await _transcribeWithParakeet(audioPath, onProgress: onProgress);
    } else {
      return await _transcribeWithWhisper(
        audioPath,
        modelType: modelType,
        language: language,
        onProgress: onProgress,
      );
    }
  }

  /// Transcribe using Parakeet (iOS/macOS)
  Future<String> _transcribeWithParakeet(
    String audioPath, {
    Function(TranscriptionProgress)? onProgress,
  }) async {
    try {
      // Start progress
      _updateProgress(0.1, 'Transcribing with Parakeet...', onProgress);

      // Transcribe
      final result = await _parakeetService.transcribeAudio(audioPath);

      // Complete
      _updateProgress(
        1.0,
        'Transcription complete!',
        onProgress,
        isComplete: true,
      );

      debugPrint(
        '[TranscriptionAdapter] ✅ Parakeet transcribed in ${result.duration.inMilliseconds}ms',
      );

      return result.text;
    } on PlatformException catch (e) {
      throw TranscriptionException('Parakeet failed: ${e.message}');
    } catch (e) {
      throw TranscriptionException('Parakeet failed: ${e.toString()}');
    }
  }

  /// Transcribe using Whisper (Android)
  Future<String> _transcribeWithWhisper(
    String audioPath, {
    WhisperModelType? modelType,
    String? language,
    Function(TranscriptionProgress)? onProgress,
  }) async {
    if (_whisperService == null) {
      throw TranscriptionException('Whisper service not available');
    }

    try {
      return await _whisperService!.transcribeAudio(
        audioPath,
        modelType: modelType,
        language: language,
        onProgress: onProgress,
      );
    } on WhisperLocalException catch (e) {
      throw TranscriptionException(e.message);
    }
  }

  /// Update and broadcast progress
  void _updateProgress(
    double progress,
    String status,
    Function(TranscriptionProgress)? onProgress, {
    bool isComplete = false,
  }) {
    final progressData = TranscriptionProgress(
      progress: progress.clamp(0.0, 1.0),
      status: status,
      isComplete: isComplete,
    );

    _transcriptionProgressController.add(progressData);
    onProgress?.call(progressData);
  }

  /// Check if transcription service is ready
  Future<bool> isReady() async {
    if (_parakeetService.isSupported) {
      return await _parakeetService.isReady();
    } else {
      return _whisperService?.isReady() ?? false;
    }
  }

  /// Get preferred model (Whisper only, returns base for Parakeet)
  Future<WhisperModelType> getPreferredModel() async {
    if (_parakeetService.isSupported) {
      return WhisperModelType.base; // Dummy value for compatibility
    } else {
      return await _whisperService?.getPreferredModel() ??
          WhisperModelType.base;
    }
  }

  /// Set preferred model (Whisper only, no-op for Parakeet)
  Future<void> setPreferredModel(WhisperModelType model) async {
    if (!_parakeetService.isSupported && _whisperService != null) {
      await _whisperService!.setPreferredModel(model);
    }
  }

  /// Get available models (Whisper only, returns empty for Parakeet)
  Future<List<WhisperModelType>> getAvailableModels() async {
    if (_parakeetService.isSupported) {
      return []; // Parakeet doesn't expose model selection
    } else {
      return await _whisperService?.getAvailableModels() ?? [];
    }
  }

  void dispose() {
    _transcriptionProgressController.close();
  }
}

/// Generic transcription exception
class TranscriptionException implements Exception {
  final String message;

  TranscriptionException(this.message);

  @override
  String toString() => message;
}
