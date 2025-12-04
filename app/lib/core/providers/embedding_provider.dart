import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/models/embedding_models.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/embedding/embedding_model_manager.dart';

/// Provider for the embedding service
///
/// This provider will be implemented by platform-specific providers:
/// - mobileEmbeddingServiceProvider (Android/iOS with flutter_gemma)
/// - desktopEmbeddingServiceProvider (macOS/Linux/Windows with Ollama)
///
/// For now, this is a placeholder that will throw an error.
/// Actual implementations will be created in issues #20 (mobile) and #22 (desktop).
final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  throw UnimplementedError(
    'Embedding service not yet implemented for this platform.\n'
    'Mobile implementation: Issue #20\n'
    'Desktop implementation: Issue #22',
  );
});

/// Provider for the embedding model manager
///
/// Manages model download lifecycle and status tracking.
final embeddingModelManagerProvider = Provider<EmbeddingModelManager>((ref) {
  final embeddingService = ref.watch(embeddingServiceProvider);
  final manager = EmbeddingModelManager(embeddingService);

  ref.onDispose(() async {
    await manager.dispose();
  });

  return manager;
});

/// State provider for embedding model status
///
/// Tracks the current status of the embedding model:
/// - notDownloaded: Model needs to be downloaded
/// - downloading: Download in progress
/// - ready: Model is ready to use
/// - error: Download or initialization failed
final embeddingModelStatusProvider =
    StateProvider<EmbeddingModelStatus>((ref) {
  return EmbeddingModelStatus.notDownloaded;
});

/// State provider for download progress
///
/// Tracks download progress from 0.0 to 1.0.
/// Only meaningful when status is downloading.
final embeddingDownloadProgressProvider = StateProvider<double>((ref) {
  return 0.0;
});

/// State provider for error message
///
/// Contains error message when status is error.
final embeddingErrorProvider = StateProvider<String?>((ref) {
  return null;
});

/// Provider for embedding dimensions
///
/// Returns the number of dimensions for embeddings on this platform:
/// - Mobile: 256 (truncated from 768)
/// - Desktop: 768 or 1024 (depends on Ollama model)
final embeddingDimensionsProvider = Provider<int>((ref) {
  final manager = ref.watch(embeddingModelManagerProvider);
  return manager.dimensions;
});
