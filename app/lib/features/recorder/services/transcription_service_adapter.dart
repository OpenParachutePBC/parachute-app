import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app/services/parakeet_service.dart';
import 'package:app/services/sherpa_onnx_service.dart';
import 'package:app/features/recorder/services/whisper_local_service.dart';
import 'package:app/features/recorder/models/whisper_models.dart'
    show WhisperModelType, TranscriptionProgress;

/// Platform-adaptive transcription service
///
/// Uses Parakeet via different implementations:
/// - iOS/macOS: FluidAudio (CoreML-based, Apple Neural Engine)
/// - Android: Sherpa-ONNX (ONNX Runtime-based)
/// - Fallback: Whisper (for legacy/testing)
///
/// This is a drop-in replacement for WhisperLocalService with the same interface.
class TranscriptionServiceAdapter {
  final ParakeetService _parakeetService = ParakeetService();
  final SherpaOnnxService _sherpaService = SherpaOnnxService();
  final WhisperLocalService? _whisperService;

  // Progress tracking
  final _transcriptionProgressController =
      StreamController<TranscriptionProgress>.broadcast();

  Stream<TranscriptionProgress> get transcriptionProgressStream =>
      _transcriptionProgressController.stream;

  bool get isUsingParakeet =>
      _parakeetService.isSupported || _sherpaService.isSupported;
  String get engineName {
    if (_parakeetService.isSupported && _parakeetService.isInitialized) {
      return 'Parakeet v3 (FluidAudio)';
    } else if (_sherpaService.isInitialized) {
      return 'Parakeet v3 (Sherpa-ONNX)';
    } else {
      return 'Whisper';
    }
  }

  TranscriptionServiceAdapter({WhisperLocalService? whisperService})
    : _whisperService = whisperService;

  /// Initialize the transcription service
  ///
  /// Platform-specific initialization:
  /// - iOS/macOS: Parakeet via FluidAudio (CoreML)
  /// - Android: Parakeet via Sherpa-ONNX
  /// - Fallback: Whisper (if Parakeet fails)
  Future<void> initialize() async {
    if (_parakeetService.isSupported) {
      // iOS/macOS: Initialize Parakeet via FluidAudio
      debugPrint(
        '[TranscriptionAdapter] Initializing Parakeet (FluidAudio)...',
      );
      try {
        await _parakeetService.initialize(version: 'v3');
        debugPrint('[TranscriptionAdapter] ✅ Parakeet (FluidAudio) ready');
      } catch (e) {
        debugPrint('[TranscriptionAdapter] ⚠️ Parakeet init failed: $e');
        throw TranscriptionException(
          'Failed to initialize Parakeet: ${e.toString()}',
        );
      }
    } else {
      // Android/other: Initialize Parakeet via Sherpa-ONNX
      debugPrint(
        '[TranscriptionAdapter] Initializing Parakeet (Sherpa-ONNX)...',
      );
      try {
        await _sherpaService.initialize();
        debugPrint('[TranscriptionAdapter] ✅ Parakeet (Sherpa-ONNX) ready');
      } catch (e) {
        debugPrint('[TranscriptionAdapter] ⚠️ Sherpa-ONNX init failed: $e');
        debugPrint('[TranscriptionAdapter] Falling back to Whisper');

        // Fallback to Whisper if Sherpa-ONNX fails
        if (_whisperService == null) {
          throw TranscriptionException(
            'Sherpa-ONNX init failed and Whisper not available: ${e.toString()}',
          );
        }

        final isReady = await _whisperService!.isReady();
        if (!isReady) {
          throw TranscriptionException(
            'Sherpa-ONNX init failed and Whisper not ready. Please download a Whisper model in Settings.',
          );
        }
      }
    }
  }

  /// Transcribe audio file
  ///
  /// [audioPath] - Absolute path to audio file (WAV, 16kHz mono)
  /// [modelType] - Only used for Whisper fallback. Ignored for Parakeet.
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
    final needsInit =
        (_parakeetService.isSupported && !_parakeetService.isInitialized) ||
        (!_parakeetService.isSupported && !_sherpaService.isInitialized);

    if (needsInit) {
      debugPrint('[TranscriptionAdapter] Lazy-initializing...');
      try {
        await initialize();
      } catch (e) {
        debugPrint('[TranscriptionAdapter] ⚠️ Lazy init failed: $e');
        // Will fall through to Whisper if initialization fails
      }
    }

    // Try Parakeet (FluidAudio on iOS/macOS)
    if (_parakeetService.isSupported && _parakeetService.isInitialized) {
      return await _transcribeWithParakeet(audioPath, onProgress: onProgress);
    }

    // Try Parakeet (Sherpa-ONNX on Android)
    if (_sherpaService.isInitialized) {
      return await _transcribeWithSherpa(audioPath, onProgress: onProgress);
    }

    // Fallback to Whisper
    return await _transcribeWithWhisper(
      audioPath,
      modelType: modelType,
      language: language,
      onProgress: onProgress,
    );
  }

  /// Transcribe using Parakeet via FluidAudio (iOS/macOS)
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
        '[TranscriptionAdapter] ✅ Parakeet (FluidAudio) transcribed in ${result.duration.inMilliseconds}ms',
      );

      return result.text;
    } on PlatformException catch (e) {
      throw TranscriptionException('Parakeet failed: ${e.message}');
    } catch (e) {
      throw TranscriptionException('Parakeet failed: ${e.toString()}');
    }
  }

  /// Transcribe using Parakeet via Sherpa-ONNX (Android)
  Future<String> _transcribeWithSherpa(
    String audioPath, {
    Function(TranscriptionProgress)? onProgress,
  }) async {
    try {
      // Start progress
      _updateProgress(0.1, 'Transcribing with Parakeet...', onProgress);

      // Transcribe
      final result = await _sherpaService.transcribeAudio(audioPath);

      // Complete
      _updateProgress(
        1.0,
        'Transcription complete!',
        onProgress,
        isComplete: true,
      );

      debugPrint(
        '[TranscriptionAdapter] ✅ Parakeet (Sherpa-ONNX) transcribed in ${result.duration.inMilliseconds}ms',
      );

      return result.text;
    } catch (e) {
      throw TranscriptionException(
        'Parakeet (Sherpa-ONNX) failed: ${e.toString()}',
      );
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
    // Check FluidAudio (iOS/macOS)
    if (_parakeetService.isSupported) {
      return await _parakeetService.isReady();
    }

    // Check Sherpa-ONNX (Android)
    if (await _sherpaService.isReady()) {
      return true;
    }

    // Check Whisper (fallback)
    return _whisperService?.isReady() ?? false;
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
