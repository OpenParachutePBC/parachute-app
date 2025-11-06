import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/core/services/file_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// File-based storage service for client-server sync architecture
///
/// Backend owns ~/Parachute/captures/ (source of truth)
/// Flutter uses lightweight local cache for temp storage and playback
///
/// Each recording consists of:
/// - An audio file (.wav or .m4a) on backend
/// - A markdown transcript file (.md) on backend
/// - Local cache for downloaded files
class StorageService {
  final FileSyncService _fileSyncService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _hasInitializedKey = 'has_initialized';
  static const String _openaiApiKeyKey = 'openai_api_key';
  static const String _geminiApiKeyKey = 'gemini_api_key';
  static const String _transcriptionModeKey = 'transcription_mode';
  static const String _preferredWhisperModelKey = 'preferred_whisper_model';
  static const String _autoTranscribeKey = 'auto_transcribe';
  static const String _titleGenerationModeKey = 'title_generation_mode';
  static const String _preferredGemmaModelKey = 'preferred_gemma_model';
  static const String _preferredSmolLMModelKey = 'preferred_smollm_model';
  static const String _huggingfaceTokenKey = 'huggingface_token';

  final FileSystemService _fileSystem = FileSystemService();
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  StorageService(this._fileSyncService);

  /// Initialize the storage service and ensure sync folder is set up
  Future<void> initialize() async {
    // If already initialized, return immediately
    if (_isInitialized) return;

    // If initialization is in progress, wait for it to complete
    if (_initializationFuture != null) {
      return _initializationFuture;
    }

    // Start initialization and store the future
    _initializationFuture = _doInitialize();
    await _initializationFuture;
  }

  Future<void> _doInitialize() async {
    try {
      debugPrint('[StorageService] Starting initialization...');

      // Initialize the file system service
      await _fileSystem.initialize();
      debugPrint('[StorageService] FileSystemService initialized');

      final prefs = await SharedPreferences.getInstance();

      // Create sample recordings on first launch
      final hasInitialized = prefs.getBool(_hasInitializedKey) ?? false;
      debugPrint('StorageService: Has initialized: $hasInitialized');
      if (!hasInitialized) {
        debugPrint('StorageService: Creating sample recordings...');
        await _createSampleRecordings();
        await prefs.setBool(_hasInitializedKey, true);
      }

      _isInitialized = true;
      _initializationFuture = null;
      debugPrint('[StorageService] Initialization complete');
    } catch (e, stackTrace) {
      debugPrint('[StorageService] Error during initialization: $e');
      debugPrint('[StorageService] Stack trace: $stackTrace');
      _initializationFuture = null;
      rethrow;
    }
  }

  /// Get the current captures folder path (replaces getSyncFolderPath)
  Future<String> getSyncFolderPath() async {
    await initialize();
    return await _fileSystem.getCapturesPath();
  }

  /// Set a new root folder path (for user configuration)
  Future<bool> setSyncFolderPath(String path) async {
    try {
      return await _fileSystem.setRootPath(path);
    } catch (e) {
      debugPrint('[StorageService] Error setting root path: $e');
      return false;
    }
  }

  /// Get the path for a recording's audio file
  Future<String> _getAudioPath(String recordingId, DateTime timestamp) async {
    final capturesPath = await _fileSystem.getCapturesPath();
    final timestampStr = FileSystemService.formatTimestampForFilename(
      timestamp,
    );
    return '$capturesPath/$timestampStr.wav';
  }

  /// Get the path for a recording's metadata markdown file (transcript)
  Future<String> _getMetadataPath(
    String recordingId,
    DateTime timestamp,
  ) async {
    final capturesPath = await _fileSystem.getCapturesPath();
    final timestampStr = FileSystemService.formatTimestampForFilename(
      timestamp,
    );
    return '$capturesPath/$timestampStr.md';
  }

  /// Get the path for a recording's JSON metadata file
  Future<String> _getJsonMetadataPath(
    String recordingId,
    DateTime timestamp,
  ) async {
    final capturesPath = await _fileSystem.getCapturesPath();
    final timestampStr = FileSystemService.formatTimestampForFilename(
      timestamp,
    );
    return '$capturesPath/$timestampStr.json';
  }

  /// Load all recordings from local filesystem (LOCAL-FIRST)
  Future<List<Recording>> getRecordings() async {
    await initialize();

    try {
      debugPrint(
        '[StorageService] Loading recordings from local filesystem...',
      );
      final capturesPath = await _fileSystem.getCapturesPath();
      final capturesDir = Directory(capturesPath);

      if (!await capturesDir.exists()) {
        debugPrint('[StorageService] Captures directory does not exist yet');
        return [];
      }

      // Find all markdown files (each represents a recording)
      final recordings = <Recording>[];
      await for (final entity in capturesDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final recording = await _loadRecordingFromMarkdown(entity);
            if (recording != null) {
              recordings.add(recording);
            }
          } catch (e) {
            debugPrint(
              '[StorageService] Error loading recording from ${entity.path}: $e',
            );
          }
        }
      }

      // Sort by timestamp (newest first)
      recordings.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      debugPrint(
        '[StorageService] Loaded ${recordings.length} recordings from filesystem',
      );
      return recordings;
    } catch (e) {
      debugPrint('[StorageService] Error loading recordings: $e');
      return [];
    }
  }

  /// Load a recording from a markdown file
  Future<Recording?> _loadRecordingFromMarkdown(File mdFile) async {
    try {
      final content = await mdFile.readAsString();
      final filename = p.basename(mdFile.path);

      // Extract timestamp from filename (e.g., "2025-11-05_14-30-22.md")
      final timestamp = FileSystemService.parseTimestampFromFilename(filename);
      if (timestamp == null) {
        debugPrint(
          '[StorageService] Could not parse timestamp from: $filename',
        );
        return null;
      }

      // Parse YAML frontmatter
      String? durationStr;
      String? source;

      final lines = content.split('\n');
      if (lines.isNotEmpty && lines[0] == '---') {
        // Find end of frontmatter
        int endIndex = -1;
        for (int i = 1; i < lines.length; i++) {
          if (lines[i] == '---') {
            endIndex = i;
            break;
          }
        }

        if (endIndex > 0) {
          // Parse frontmatter fields
          for (int i = 1; i < endIndex; i++) {
            final line = lines[i];
            if (line.contains(':')) {
              final parts = line.split(':');
              final key = parts[0].trim();
              final value = parts.sublist(1).join(':').trim();

              if (key == 'duration') durationStr = value;
              if (key == 'source') source = value;
            }
          }
        }
      }

      // Extract transcript (everything after frontmatter)
      String transcript = content;
      if (lines.isNotEmpty && lines[0] == '---') {
        final endIndex = lines.indexOf('---', 1);
        if (endIndex > 0 && endIndex + 1 < lines.length) {
          transcript = lines.sublist(endIndex + 1).join('\n').trim();
        }
      }

      // Parse duration (format: "MM:SS")
      Duration duration = Duration.zero;
      if (durationStr != null) {
        final parts = durationStr.split(':');
        if (parts.length == 2) {
          final minutes = int.tryParse(parts[0]) ?? 0;
          final seconds = int.tryParse(parts[1]) ?? 0;
          duration = Duration(minutes: minutes, seconds: seconds);
        }
      }

      // Check if corresponding audio file exists
      final audioPath = mdFile.path.replaceAll('.md', '.wav');
      final audioExists = await File(audioPath).exists();

      // Generate title from first line of transcript
      final title = _extractTitleFromTranscript(transcript);

      // Get file size
      final stat = await mdFile.stat();
      final fileSizeKB = stat.size / 1024;

      // Determine recording source
      final recordingSource = source == 'omiDevice'
          ? RecordingSource.omiDevice
          : RecordingSource.phone;

      return Recording(
        id: filename.replaceAll('.md', ''), // Use timestamp as ID
        title: title,
        filePath: audioExists ? audioPath : mdFile.path,
        timestamp: timestamp,
        duration: duration,
        tags: [],
        transcript: transcript,
        fileSizeKB: fileSizeKB,
        source: recordingSource,
        deviceId: recordingSource == RecordingSource.omiDevice
            ? 'unknown'
            : null,
        buttonTapCount: null,
      );
    } catch (e) {
      debugPrint('[StorageService] Error loading recording from markdown: $e');
      return null;
    }
  }

  /// Extract title from transcript (first line or first 50 chars)
  String _extractTitleFromTranscript(String transcript) {
    if (transcript.isEmpty) return 'Untitled';

    final firstLine = transcript.split('\n').first.trim();
    if (firstLine.length <= 50) return firstLine;

    return '${firstLine.substring(0, 47)}...';
  }

  /// Save a recording - LOCAL-FIRST, backend sync is optional
  /// Returns the recording ID (timestamp-based for local files)
  ///
  /// NOTE: Backend sync is being deprecated in favor of Git-based sync.
  /// This method now primarily ensures the recording exists in local filesystem.
  Future<String?> saveRecording(Recording recording) async {
    if (!_isInitialized && _initializationFuture == null) {
      await initialize();
    }

    try {
      // Check if audio file exists locally
      final audioFile = File(recording.filePath);
      if (!await audioFile.exists()) {
        debugPrint(
          '[StorageService] Audio file not found: ${recording.filePath}',
        );
        return null;
      }

      // Ensure the recording is saved to captures folder
      final capturesPath = await _fileSystem.getCapturesPath();
      final timestamp = FileSystemService.formatTimestampForFilename(
        recording.timestamp,
      );

      // Save markdown file with transcript
      final mdPath = p.join(capturesPath, '$timestamp.md');
      final mdFile = File(mdPath);

      if (!await mdFile.exists()) {
        final markdown = _generateMarkdown(recording);
        await mdFile.writeAsString(markdown);
        debugPrint('[StorageService] Saved recording locally: $mdPath');
      }

      // Copy audio file if not already in captures folder
      final audioDestPath = p.join(capturesPath, '$timestamp.wav');
      if (recording.filePath != audioDestPath &&
          !await File(audioDestPath).exists()) {
        await audioFile.copy(audioDestPath);
        debugPrint('[StorageService] Copied audio to: $audioDestPath');
      }

      // Backend sync is optional and will be handled by Git sync in the future
      debugPrint(
        '[StorageService] Recording saved locally (backend sync deprecated)',
      );

      return timestamp; // Return timestamp as ID for local-first architecture
    } catch (e) {
      debugPrint('[StorageService] Error saving recording locally: $e');
      return null;
    }
  }

  /// Upload transcript for a recording
  Future<bool> uploadTranscript({
    required String filename,
    required String transcript,
    required String transcriptionMode,
    String? title,
    String? modelUsed,
  }) async {
    try {
      await _fileSyncService.uploadTranscript(
        filename: filename,
        transcript: transcript,
        transcriptionMode: transcriptionMode,
        title: title,
        modelUsed: modelUsed,
      );
      debugPrint('[StorageService] Transcript uploaded for $filename');
      return true;
    } catch (e) {
      debugPrint('[StorageService] Error uploading transcript: $e');
      return false;
    }
  }

  /// Generate markdown content from recording
  String _generateMarkdown(Recording recording) {
    final buffer = StringBuffer();

    // Frontmatter
    buffer.writeln('---');
    buffer.writeln('id: ${recording.id}');
    buffer.writeln('title: ${recording.title}');
    buffer.writeln('created: ${recording.timestamp.toIso8601String()}');
    buffer.writeln('duration: ${recording.duration.inSeconds}');
    buffer.writeln('fileSize: ${recording.fileSizeKB}');
    buffer.writeln('source: ${recording.source}');

    if (recording.deviceId != null) {
      buffer.writeln('deviceId: ${recording.deviceId}');
    }

    if (recording.buttonTapCount != null) {
      buffer.writeln('buttonTapCount: ${recording.buttonTapCount}');
    }

    if (recording.tags.isNotEmpty) {
      buffer.writeln('tags:');
      for (final tag in recording.tags) {
        buffer.writeln('  - $tag');
      }
    }

    buffer.writeln('---');
    buffer.writeln();

    // Content
    buffer.writeln('# ${recording.title}');
    buffer.writeln();

    if (recording.transcript.isNotEmpty) {
      buffer.writeln('## Transcription');
      buffer.writeln();
      buffer.writeln(recording.transcript);
    }

    return buffer.toString();
  }

  /// Update an existing recording
  Future<bool> updateRecording(Recording updatedRecording) async {
    try {
      debugPrint('[StorageService] Updating recording: ${updatedRecording.id}');

      // Extract filename from URL or path
      final filename = p.basename(updatedRecording.filePath);

      // If transcript exists, upload it
      if (updatedRecording.transcript.isNotEmpty) {
        debugPrint(
          '[StorageService] Uploading transcript for $filename (${updatedRecording.transcript.length} chars)',
        );

        final transcriptionMode = await getTranscriptionMode();
        final success = await uploadTranscript(
          filename: filename,
          transcript: updatedRecording.transcript,
          transcriptionMode: transcriptionMode,
          title: updatedRecording.title,
        );

        if (success) {
          debugPrint('[StorageService] ✅ Transcript uploaded successfully');
        } else {
          debugPrint('[StorageService] ❌ Transcript upload failed');
        }

        return success;
      }

      debugPrint('[StorageService] No transcript to upload');
      return true;
    } catch (e) {
      debugPrint('[StorageService] Error updating recording: $e');
      return false;
    }
  }

  /// Delete a recording from backend
  Future<bool> deleteRecording(String recordingId) async {
    try {
      // First, get the recording to find its filename
      final recordings = await getRecordings();
      final recording = recordings.firstWhere(
        (r) => r.id == recordingId,
        orElse: () => throw Exception('Recording not found'),
      );

      // Extract filename from URL (e.g., "2025-10-25_14-30-22.wav")
      final filename = p.basename(recording.filePath);

      // Delete from backend
      await _fileSyncService.deleteCapture(filename);
      debugPrint('[StorageService] Deleted recording from backend: $filename');

      // Clean up local cache if exists
      await _cleanupLocalCache(filename);

      return true;
    } catch (e) {
      debugPrint('[StorageService] Error deleting recording: $e');
      return false;
    }
  }

  /// Clean up local cached files
  Future<void> _cleanupLocalCache(String filename) async {
    try {
      final cacheDir = await _fileSyncService.getCacheDir();
      final cachedFile = File(p.join(cacheDir, filename));

      if (await cachedFile.exists()) {
        await cachedFile.delete();
        debugPrint('[StorageService] Deleted cached file: $filename');
      }
    } catch (e) {
      debugPrint('[StorageService] Error cleaning cache: $e');
    }
  }

  /// Get a single recording by ID
  Future<Recording?> getRecording(String recordingId) async {
    debugPrint('[StorageService] Looking for recording with ID: $recordingId');
    final recordings = await getRecordings();
    try {
      final found = recordings.firstWhere((r) => r.id == recordingId);
      debugPrint('[StorageService] Found recording: ${found.id}');
      return found;
    } catch (e) {
      debugPrint(
        '[StorageService] Recording not found in list of ${recordings.length} recordings',
      );
      debugPrint(
        '[StorageService] Available IDs: ${recordings.map((r) => r.id).take(5).join(", ")}...',
      );
      return null;
    }
  }

  /// Get local file path for playback (downloads if not cached)
  Future<String?> getLocalFilePath(String recordingId) async {
    try {
      final recording = await getRecording(recordingId);
      if (recording == null) {
        debugPrint('[StorageService] Recording not found: $recordingId');
        return null;
      }

      // Extract filename from URL
      final filename = p.basename(recording.filePath);

      // Download to cache (returns cached path if already exists)
      final localPath = await _fileSyncService.downloadCapture(filename);
      debugPrint('[StorageService] Local file path: $localPath');

      return localPath;
    } catch (e) {
      debugPrint('[StorageService] Error getting local file path: $e');
      return null;
    }
  }

  /// Create sample recordings for demo purposes
  Future<void> _createSampleRecordings() async {
    final now = DateTime.now();

    final timestamp1 = now.subtract(const Duration(hours: 2));
    final timestamp2 = now.subtract(const Duration(days: 1));
    final timestamp3 = now.subtract(const Duration(hours: 5));

    final sampleRecordings = [
      Recording(
        id: 'sample_1',
        title: 'Welcome to Parachute',
        filePath: await _getAudioPath('sample_1', timestamp1),
        timestamp: timestamp1,
        duration: const Duration(minutes: 1, seconds: 30),
        tags: ['welcome', 'tutorial'],
        transcript:
            'Welcome to Parachute, your personal voice recording assistant. '
            'This app helps you capture thoughts, ideas, and important moments with ease.',
        fileSizeKB: 450,
      ),
      Recording(
        id: 'sample_2',
        title: 'Meeting Notes',
        filePath: await _getAudioPath('sample_2', timestamp2),
        timestamp: timestamp2,
        duration: const Duration(minutes: 15, seconds: 45),
        tags: ['work', 'meeting', 'project-alpha'],
        transcript:
            'Today we discussed the new features for Project Alpha. '
            'Key decisions: 1) Move deadline to next quarter, 2) Add two more developers to the team, '
            '3) Focus on mobile-first approach.',
        fileSizeKB: 2340,
      ),
      Recording(
        id: 'sample_3',
        title: 'Quick Reminder',
        filePath: await _getAudioPath('sample_3', timestamp3),
        timestamp: timestamp3,
        duration: const Duration(seconds: 45),
        tags: ['personal', 'reminder'],
        transcript:
            'Remember to call the dentist tomorrow morning to schedule the appointment. '
            'Also, pick up groceries on the way home.',
        fileSizeKB: 180,
      ),
    ];

    for (final recording in sampleRecordings) {
      await saveRecording(recording);

      // Create empty placeholder audio files
      final audioFile = File(recording.filePath);
      if (!await audioFile.exists()) {
        await audioFile.create(recursive: true);
      }
    }
  }

  /// Clear all recordings
  Future<void> clearAllRecordings() async {
    final recordings = await getRecordings();
    for (final recording in recordings) {
      await deleteRecording(recording.id);
    }
  }

  // OpenAI API Key Management (kept in SharedPreferences as it's config, not data)
  Future<String?> getOpenAIApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_openaiApiKeyKey);
    } catch (e) {
      debugPrint('Error getting OpenAI API key: $e');
      return null;
    }
  }

  Future<bool> saveOpenAIApiKey(String apiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_openaiApiKeyKey, apiKey.trim());
    } catch (e) {
      debugPrint('Error saving OpenAI API key: $e');
      return false;
    }
  }

  Future<bool> deleteOpenAIApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_openaiApiKeyKey);
    } catch (e) {
      debugPrint('Error deleting OpenAI API key: $e');
      return false;
    }
  }

  Future<bool> hasOpenAIApiKey() async {
    final apiKey = await getOpenAIApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }

  // Gemini API Key Management
  Future<String?> getGeminiApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_geminiApiKeyKey);
    } catch (e) {
      debugPrint('Error getting Gemini API key: $e');
      return null;
    }
  }

  Future<bool> saveGeminiApiKey(String apiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_geminiApiKeyKey, apiKey.trim());
    } catch (e) {
      debugPrint('Error saving Gemini API key: $e');
      return false;
    }
  }

  Future<bool> deleteGeminiApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_geminiApiKeyKey);
    } catch (e) {
      debugPrint('Error deleting Gemini API key: $e');
      return false;
    }
  }

  Future<bool> hasGeminiApiKey() async {
    final apiKey = await getGeminiApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }

  // Local Whisper Configuration

  /// Get transcription mode (api or local)
  Future<String> getTranscriptionMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_transcriptionModeKey) ?? 'api';
    } catch (e) {
      debugPrint('Error getting transcription mode: $e');
      return 'api';
    }
  }

  /// Set transcription mode
  Future<bool> setTranscriptionMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_transcriptionModeKey, mode);
    } catch (e) {
      debugPrint('Error setting transcription mode: $e');
      return false;
    }
  }

  /// Get preferred Whisper model
  Future<String?> getPreferredWhisperModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredWhisperModelKey);
    } catch (e) {
      debugPrint('Error getting preferred Whisper model: $e');
      return null;
    }
  }

  /// Set preferred Whisper model
  Future<bool> setPreferredWhisperModel(String modelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_preferredWhisperModelKey, modelName);
    } catch (e) {
      debugPrint('Error setting preferred Whisper model: $e');
      return false;
    }
  }

  /// Get auto-transcribe setting
  Future<bool> getAutoTranscribe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoTranscribeKey) ?? false;
    } catch (e) {
      debugPrint('Error getting auto-transcribe setting: $e');
      return false;
    }
  }

  /// Set auto-transcribe setting
  Future<bool> setAutoTranscribe(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_autoTranscribeKey, enabled);
    } catch (e) {
      debugPrint('Error setting auto-transcribe: $e');
      return false;
    }
  }

  // Title Generation Configuration

  /// Get title generation mode (api or local)
  Future<String> getTitleGenerationMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_titleGenerationModeKey) ?? 'api';
    } catch (e) {
      debugPrint('Error getting title generation mode: $e');
      return 'api';
    }
  }

  /// Set title generation mode
  Future<bool> setTitleGenerationMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_titleGenerationModeKey, mode);
    } catch (e) {
      debugPrint('Error setting title generation mode: $e');
      return false;
    }
  }

  /// Get preferred Gemma model
  Future<String?> getPreferredGemmaModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredGemmaModelKey);
    } catch (e) {
      debugPrint('Error getting preferred Gemma model: $e');
      return null;
    }
  }

  /// Set preferred Gemma model
  Future<bool> setPreferredGemmaModel(String modelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_preferredGemmaModelKey, modelName);
    } catch (e) {
      debugPrint('Error setting preferred Gemma model: $e');
      return false;
    }
  }

  // SmolLM Configuration

  /// Get preferred SmolLM model
  Future<String?> getPreferredSmolLMModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredSmolLMModelKey);
    } catch (e) {
      debugPrint('Error getting preferred SmolLM model: $e');
      return null;
    }
  }

  /// Set preferred SmolLM model
  Future<bool> setPreferredSmolLMModel(String modelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_preferredSmolLMModelKey, modelName);
    } catch (e) {
      debugPrint('Error setting preferred SmolLM model: $e');
      return false;
    }
  }

  // HuggingFace Token Management

  /// Get HuggingFace token for Gemma model downloads
  Future<String?> getHuggingFaceToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_huggingfaceTokenKey);
    } catch (e) {
      debugPrint('Error getting HuggingFace token: $e');
      return null;
    }
  }

  /// Save HuggingFace token
  Future<bool> saveHuggingFaceToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_huggingfaceTokenKey, token.trim());
    } catch (e) {
      debugPrint('Error saving HuggingFace token: $e');
      return false;
    }
  }

  /// Delete HuggingFace token
  Future<bool> deleteHuggingFaceToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_huggingfaceTokenKey);
    } catch (e) {
      debugPrint('Error deleting HuggingFace token: $e');
      return false;
    }
  }

  /// Check if HuggingFace token exists
  Future<bool> hasHuggingFaceToken() async {
    final token = await getHuggingFaceToken();
    return token != null && token.isNotEmpty;
  }

  // GitHub Token Management

  /// Get GitHub Personal Access Token for Git sync
  // TODO: Use secure storage when code signing is enabled
  // For now using SharedPreferences due to keychain entitlement requiring code signing
  Future<String?> getGitHubToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('github_token');
    } catch (e) {
      debugPrint('Error getting GitHub token: $e');
      return null;
    }
  }

  /// Save GitHub Personal Access Token
  Future<bool> saveGitHubToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString('github_token', token);
    } catch (e) {
      debugPrint('Error saving GitHub token: $e');
      return false;
    }
  }

  /// Delete GitHub Personal Access Token
  Future<bool> deleteGitHubToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove('github_token');
    } catch (e) {
      debugPrint('Error deleting GitHub token: $e');
      return false;
    }
  }

  /// Check if GitHub token exists
  Future<bool> hasGitHubToken() async {
    final token = await getGitHubToken();
    return token != null && token.isNotEmpty;
  }

  // GitHub Repository URL Management

  /// Get GitHub repository URL for Git sync
  Future<String?> getGitHubRepositoryUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('github_repository_url');
    } catch (e) {
      debugPrint('Error getting GitHub repository URL: $e');
      return null;
    }
  }

  /// Save GitHub repository URL
  Future<bool> saveGitHubRepositoryUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString('github_repository_url', url);
    } catch (e) {
      debugPrint('Error saving GitHub repository URL: $e');
      return false;
    }
  }

  /// Delete GitHub repository URL
  Future<bool> deleteGitHubRepositoryUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove('github_repository_url');
    } catch (e) {
      debugPrint('Error deleting GitHub repository URL: $e');
      return false;
    }
  }

  /// Check if Git sync is enabled
  Future<bool> isGitSyncEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('git_sync_enabled') ?? false;
    } catch (e) {
      debugPrint('Error checking Git sync enabled: $e');
      return false;
    }
  }

  /// Set Git sync enabled status
  Future<bool> setGitSyncEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool('git_sync_enabled', enabled);
    } catch (e) {
      debugPrint('Error setting Git sync enabled: $e');
      return false;
    }
  }
}
