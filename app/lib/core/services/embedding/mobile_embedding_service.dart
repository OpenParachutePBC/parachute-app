import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma_embedder/flutter_gemma_embedder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/models/embedding_models.dart';

/// Mobile embedding service using flutter_gemma_embedder
///
/// Generates text embeddings on-device using Google's EmbeddingGemma model.
/// Supports Android and iOS with GPU acceleration where available.
///
/// Key features:
/// - 768-dimensional embeddings (truncated to 256 for speed)
/// - Matryoshka embeddings - can truncate without quality loss
/// - <200MB RAM usage with quantization
/// - No network required after model download
class MobileEmbeddingService implements EmbeddingService {
  final FlutterGemmaEmbedder _embedder = FlutterGemmaEmbedder.instance;
  EmbeddingModel? _model;
  bool _isDisposed = false;

  /// Target dimensions (using Matryoshka truncation from 768)
  static const int _dimensions = 256;

  /// Model configuration
  static const EmbeddingGemmaModelType _modelType =
      EmbeddingGemmaModelType.standard;

  @override
  int get dimensions => _dimensions;

  @override
  Future<bool> isReady() async {
    if (_isDisposed) {
      debugPrint('[MobileEmbedding] Service is disposed');
      return false;
    }

    // Check if model is loaded in memory
    if (_model != null) {
      debugPrint('[MobileEmbedding] Model already loaded in memory');
      return true;
    }

    // Check if model file exists on disk
    try {
      final modelPath = await _getModelPath();
      final modelFile = File(modelPath);
      final exists = await modelFile.exists();

      if (exists) {
        debugPrint('[MobileEmbedding] Model file exists, loading...');
        await _loadModel();
        return _model != null;
      }

      debugPrint('[MobileEmbedding] Model file does not exist');
      return false;
    } catch (e) {
      debugPrint('[MobileEmbedding] Error checking if ready: $e');
      return false;
    }
  }

  @override
  Future<bool> needsDownload() async {
    if (_isDisposed) {
      debugPrint('[MobileEmbedding] Service is disposed');
      return false;
    }

    try {
      final modelPath = await _getModelPath();
      final modelFile = File(modelPath);
      final exists = await modelFile.exists();

      debugPrint(
        '[MobileEmbedding] Model file ${exists ? 'exists' : 'needs download'}: $modelPath',
      );
      return !exists;
    } catch (e) {
      debugPrint('[MobileEmbedding] Error checking if download needed: $e');
      return true;
    }
  }

  @override
  Stream<double> downloadModel() async* {
    if (_isDisposed) {
      throw Exception('Service is disposed');
    }

    debugPrint('[MobileEmbedding] Starting model download...');
    debugPrint('[MobileEmbedding] Download URL: ${_modelType.downloadUrl}');
    debugPrint('[MobileEmbedding] Model size: ${_modelType.formattedSize}');

    try {
      // Check if already downloaded
      if (!await needsDownload()) {
        debugPrint('[MobileEmbedding] ✅ Model already downloaded');
        yield 1.0;
        return;
      }

      // Get model storage path
      final modelPath = await _getModelPath();
      final modelFile = File(modelPath);

      // Create parent directory if needed
      await modelFile.parent.create(recursive: true);

      // Download the model file with progress tracking
      debugPrint('[MobileEmbedding] Downloading to: $modelPath');

      final request = http.Request('GET', Uri.parse(_modelType.downloadUrl));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download model: HTTP ${response.statusCode}',
        );
      }

      final totalBytes = response.contentLength ?? 0;
      if (totalBytes == 0) {
        throw Exception('Server did not provide content length');
      }

      int downloadedBytes = 0;
      final chunks = <List<int>>[];

      await for (final chunk in response.stream) {
        downloadedBytes += chunk.length;
        chunks.add(chunk);

        final progress = downloadedBytes / totalBytes;
        yield progress;

        if (downloadedBytes % (1024 * 1024) == 0) {
          // Log every MB
          debugPrint(
            '[MobileEmbedding] Download progress: ${(progress * 100).toStringAsFixed(1)}%',
          );
        }
      }

      // Write all chunks to file
      debugPrint('[MobileEmbedding] Writing model file...');
      final bytes = chunks.expand((chunk) => chunk).toList();
      await modelFile.writeAsBytes(bytes);

      debugPrint('[MobileEmbedding] ✅ Model downloaded successfully');
      debugPrint('[MobileEmbedding] File size: ${bytes.length} bytes');

      yield 1.0;
    } catch (e, stackTrace) {
      debugPrint('[MobileEmbedding] ❌ Download failed: $e');
      debugPrint('[MobileEmbedding] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    if (_isDisposed) {
      throw Exception('Service is disposed');
    }

    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    // Ensure model is loaded
    if (_model == null) {
      final ready = await isReady();
      if (!ready) {
        throw Exception(
          'Model is not ready. Please download the model first.',
        );
      }
    }

    try {
      debugPrint('[MobileEmbedding] Embedding text (${text.length} chars)');

      // Generate 768-dimensional embedding
      final fullEmbedding = await _model!.encode(text);

      // Truncate to 256 dimensions (Matryoshka)
      final truncated = EmbeddingDimensionHelper.truncate(
        fullEmbedding,
        _dimensions,
        renormalize: true,
      );

      debugPrint('[MobileEmbedding] ✅ Generated embedding (${truncated.length}d)');
      return truncated;
    } catch (e, stackTrace) {
      debugPrint('[MobileEmbedding] ❌ Embedding failed: $e');
      debugPrint('[MobileEmbedding] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (_isDisposed) {
      throw Exception('Service is disposed');
    }

    if (texts.isEmpty) {
      return [];
    }

    for (final text in texts) {
      if (text.trim().isEmpty) {
        throw ArgumentError('All texts must be non-empty');
      }
    }

    // Ensure model is loaded
    if (_model == null) {
      final ready = await isReady();
      if (!ready) {
        throw Exception(
          'Model is not ready. Please download the model first.',
        );
      }
    }

    try {
      debugPrint('[MobileEmbedding] Embedding batch of ${texts.length} texts');

      // Generate 768-dimensional embeddings
      final fullEmbeddings = await _model!.batchEncode(texts);

      // Truncate each to 256 dimensions (Matryoshka)
      final truncatedEmbeddings = fullEmbeddings.map((embedding) {
        return EmbeddingDimensionHelper.truncate(
          embedding,
          _dimensions,
          renormalize: true,
        );
      }).toList();

      debugPrint(
        '[MobileEmbedding] ✅ Generated ${truncatedEmbeddings.length} embeddings (${_dimensions}d each)',
      );
      return truncatedEmbeddings;
    } catch (e, stackTrace) {
      debugPrint('[MobileEmbedding] ❌ Batch embedding failed: $e');
      debugPrint('[MobileEmbedding] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    debugPrint('[MobileEmbedding] Disposing service...');

    try {
      if (_model != null) {
        await _model!.dispose();
        _model = null;
        debugPrint('[MobileEmbedding] ✅ Model disposed');
      }
    } catch (e) {
      debugPrint('[MobileEmbedding] Error disposing model: $e');
    }

    _isDisposed = true;
    debugPrint('[MobileEmbedding] Service disposed');
  }

  /// Get the local path where the model should be stored
  Future<String> _getModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${dir.path}/models');

    // Extract filename from URL
    final uri = Uri.parse(_modelType.downloadUrl);
    final filename = uri.pathSegments.last;

    return '${modelsDir.path}/$filename';
  }

  /// Load the model from disk into memory
  Future<void> _loadModel() async {
    if (_model != null) {
      debugPrint('[MobileEmbedding] Model already loaded');
      return;
    }

    try {
      debugPrint('[MobileEmbedding] Loading model from disk...');

      final modelPath = await _getModelPath();
      final modelFile = File(modelPath);

      if (!await modelFile.exists()) {
        throw Exception('Model file not found: $modelPath');
      }

      // Create model instance
      _model = await _embedder.createModel(
        modelPath: modelPath,
        modelType: EmbeddingModelType.embeddingGemma300M,
        dimensions: 768, // Full dimensions (will truncate to 256)
        taskType: EmbeddingTaskType.retrieval,
        backend: PreferredBackend.gpu, // Use GPU if available
      );

      // Initialize the model
      await _model!.initialize();

      debugPrint('[MobileEmbedding] ✅ Model loaded successfully');
      debugPrint('[MobileEmbedding] Model path: $modelPath');
      debugPrint('[MobileEmbedding] Backend: GPU (if available)');
      debugPrint('[MobileEmbedding] Full dimensions: 768');
      debugPrint('[MobileEmbedding] Truncated dimensions: $_dimensions');
    } catch (e, stackTrace) {
      debugPrint('[MobileEmbedding] ❌ Failed to load model: $e');
      debugPrint('[MobileEmbedding] Stack trace: $stackTrace');
      _model = null;
      rethrow;
    }
  }
}
