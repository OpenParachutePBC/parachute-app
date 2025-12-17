import 'dart:io';
import 'package:yaml/yaml.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/file_system_service.dart';
import '../models/journal_day.dart';
import '../models/journal_entry.dart';
import 'para_id_service.dart';

/// Service for reading and writing journal files.
///
/// Handles parsing markdown files with YAML frontmatter and H1-delimited
/// entries in the format: `# para:abc123 Title here`
///
/// Uses FileSystemService for all file operations.
class JournalService {
  final String _vaultPath;
  final String _journalFolderName;
  final ParaIdService _paraIdService;
  final FileSystemService _fileSystemService;
  final _log = logger.createLogger('JournalService');

  JournalService._({
    required String vaultPath,
    required String journalFolderName,
    required ParaIdService paraIdService,
    required FileSystemService fileSystemService,
  })  : _vaultPath = vaultPath,
        _journalFolderName = journalFolderName,
        _paraIdService = paraIdService,
        _fileSystemService = fileSystemService;

  /// Factory constructor that uses FileSystemService for configuration
  static Future<JournalService> create({
    required FileSystemService fileSystemService,
    required ParaIdService paraIdService,
  }) async {
    final vaultPath = await fileSystemService.getRootPath();
    final journalFolderName = fileSystemService.getJournalFolderName();
    return JournalService._(
      vaultPath: vaultPath,
      journalFolderName: journalFolderName,
      paraIdService: paraIdService,
      fileSystemService: fileSystemService,
    );
  }

  /// Path to journals directory
  String get journalsPath => '$_vaultPath/$_journalFolderName';

  /// Ensure journals directory exists
  Future<void> ensureDirectoryExists() async {
    final created = await _fileSystemService.ensureDirectoryExists(journalsPath);
    if (created) {
      _log.info('Ensured journals directory exists');
    }
  }

  /// Get the file path for a specific date
  String getFilePath(DateTime date) {
    final dateStr = _formatDate(date);
    return '$journalsPath/$dateStr.md';
  }

  /// Load a journal day from disk
  ///
  /// Returns an empty journal if the file doesn't exist.
  Future<JournalDay> loadDay(DateTime date) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final filePath = getFilePath(normalizedDate);

    if (!await _fileSystemService.fileExists(filePath)) {
      _log.debug('Journal file not found, returning empty', data: {'date': _formatDate(normalizedDate)});
      return JournalDay.empty(normalizedDate);
    }

    try {
      final content = await _fileSystemService.readFileAsString(filePath);
      if (content == null) {
        _log.warn('Could not read journal file', data: {'date': _formatDate(normalizedDate)});
        return JournalDay.empty(normalizedDate);
      }

      final journal = _parseJournalFile(content, normalizedDate);

      // Register any para IDs we found
      for (final entry in journal.entries) {
        await _paraIdService.register(entry.id);
      }

      _log.debug('Loaded journal', data: {
        'date': _formatDate(normalizedDate),
        'entries': journal.entryCount,
      });

      return journal;
    } catch (e, st) {
      _log.error('Failed to load journal', error: e, stackTrace: st, data: {'date': _formatDate(normalizedDate)});
      rethrow;
    }
  }

  /// Load today's journal
  Future<JournalDay> loadToday() => loadDay(DateTime.now());

  /// Save a journal day to disk
  Future<void> saveDay(JournalDay journal) async {
    await ensureDirectoryExists();

    final filePath = '$_vaultPath/${journal.filePath}';
    final content = _serializeJournal(journal);

    try {
      final success = await _fileSystemService.writeFileAsString(filePath, content);
      if (!success) {
        throw Exception('Failed to write journal file');
      }
      _log.debug('Saved journal', data: {
        'date': journal.dateString,
        'entries': journal.entryCount,
      });
    } catch (e, st) {
      _log.error('Failed to save journal', error: e, stackTrace: st, data: {'date': journal.dateString});
      rethrow;
    }
  }

  /// Add a new entry to a journal day (uses surgical file append)
  ///
  /// Appends the entry to the file without rewriting existing content.
  /// This preserves any external edits to the file.
  Future<({JournalEntry entry, JournalDay journal})> addEntry({
    required DateTime date,
    required String title,
    required String content,
    JournalEntryType type = JournalEntryType.text,
    String? audioPath,
    String? linkedFilePath,
    int? durationSeconds,
  }) async {
    // Use surgical append - preserves external edits
    final entry = await appendEntryToFile(
      date: date,
      title: title,
      content: content,
      type: type,
      audioPath: audioPath,
      linkedFilePath: linkedFilePath,
      durationSeconds: durationSeconds,
    );

    // Reload the journal to get updated state
    final journal = await loadDay(date);

    return (entry: entry, journal: journal);
  }

  /// Add a text entry to today's journal
  /// Returns both the entry and updated journal for optimistic UI updates.
  Future<({JournalEntry entry, JournalDay journal})> addTextEntry({
    required String content,
    String? title,
  }) async {
    final now = DateTime.now();
    final defaultTitle = _formatTime(now);

    return addEntry(
      date: now,
      title: title ?? defaultTitle,
      content: content,
      type: JournalEntryType.text,
    );
  }

  /// Add a voice entry to today's journal
  ///
  /// Copies the audio file to the journal assets folder and stores the relative path.
  /// Returns both the entry and updated journal for optimistic UI updates.
  Future<({JournalEntry entry, JournalDay journal})> addVoiceEntry({
    required String transcript,
    required String audioPath,
    required int durationSeconds,
    String? title,
  }) async {
    final now = DateTime.now();
    final defaultTitle = _formatTime(now);

    // Ensure assets directory exists
    final assetsPath = '$journalsPath/assets';
    await _fileSystemService.ensureDirectoryExists(assetsPath);

    // Generate filename based on timestamp
    final audioFilename = '${_formatDate(now)}_${_formatTime(now).replaceAll(':', '-')}.wav';
    final destPath = '$assetsPath/$audioFilename';
    final relativePath = '$_journalFolderName/assets/$audioFilename';

    // Copy the audio file
    final sourceFile = File(audioPath);
    if (await sourceFile.exists()) {
      try {
        await sourceFile.copy(destPath);
        _log.debug('Copied audio file to journal assets', data: {'path': relativePath});
      } catch (e) {
        _log.warn('Could not copy audio file', data: {'error': e.toString()});
      }

      // Only delete temp file if we have a transcript (non-streaming mode)
      // In streaming mode (empty transcript), we need the temp file for transcription
      if (transcript.isNotEmpty) {
        try {
          await sourceFile.delete();
        } catch (e) {
          _log.warn('Could not delete temp audio file', data: {'error': e.toString()});
        }
      }
    } else {
      _log.warn('Audio file not found', data: {'path': audioPath});
    }

    return addEntry(
      date: now,
      title: title ?? defaultTitle,
      content: transcript,
      type: JournalEntryType.voice,
      audioPath: relativePath,
      durationSeconds: durationSeconds,
    );
  }

  /// Add a linked entry (for long recordings moved to separate files)
  /// Returns both the entry and updated journal for optimistic UI updates.
  Future<({JournalEntry entry, JournalDay journal})> addLinkedEntry({
    required String linkedFilePath,
    String? audioPath,
    int? durationSeconds,
    String? title,
  }) async {
    final now = DateTime.now();
    final defaultTitle = _formatTime(now);

    return addEntry(
      date: now,
      title: title ?? defaultTitle,
      content: '',
      type: JournalEntryType.linked,
      linkedFilePath: linkedFilePath,
      audioPath: audioPath,
      durationSeconds: durationSeconds,
    );
  }

  /// Update an existing entry (uses surgical file edit)
  Future<void> updateEntry(DateTime date, JournalEntry entry) async {
    await updateEntryInFile(date, entry);
  }

  /// Delete an entry (uses surgical file edit)
  Future<void> deleteEntry(DateTime date, String entryId) async {
    await deleteEntryFromFile(date, entryId);

    _log.info('Deleted journal entry', data: {
      'date': _formatDate(date),
      'id': entryId,
    });
  }

  // ============================================================
  // Surgical File Operations
  // ============================================================
  // These methods modify specific parts of the file without rewriting
  // everything, which is safer when files may be edited externally.

  /// Append an entry to the end of a journal file
  ///
  /// This is the safest operation - it only appends, never overwrites.
  /// External changes to the file are preserved.
  Future<JournalEntry> appendEntryToFile({
    required DateTime date,
    required String title,
    required String content,
    JournalEntryType type = JournalEntryType.text,
    String? audioPath,
    String? linkedFilePath,
    int? durationSeconds,
  }) async {
    await ensureDirectoryExists();

    final normalizedDate = DateTime(date.year, date.month, date.day);
    final filePath = getFilePath(normalizedDate);
    final id = await _paraIdService.generate();

    final entry = JournalEntry(
      id: id,
      title: title,
      content: content,
      type: type,
      createdAt: DateTime.now(),
      audioPath: audioPath,
      linkedFilePath: linkedFilePath,
      durationSeconds: durationSeconds,
    );

    // Read existing file content (or create new)
    String existingContent = '';
    bool fileExists = await _fileSystemService.fileExists(filePath);
    if (fileExists) {
      existingContent = await _fileSystemService.readFileAsString(filePath) ?? '';
    }

    String newContent;
    if (existingContent.isEmpty) {
      // New file - create with frontmatter
      newContent = _createNewFileWithEntry(normalizedDate, entry, audioPath);
    } else {
      // Existing file - append entry and update frontmatter if needed
      newContent = _appendEntryToContent(existingContent, entry, audioPath);
    }

    final success = await _fileSystemService.writeFileAsString(filePath, newContent);
    if (!success) {
      throw Exception('Failed to append entry to journal file');
    }

    _log.info('Appended entry to journal', data: {
      'date': _formatDate(normalizedDate),
      'id': id,
      'type': type.name,
    });

    return entry;
  }

  /// Update a specific entry block in the file
  ///
  /// Finds the block by its para:ID and replaces only that section.
  /// Everything else in the file is preserved byte-for-byte.
  Future<void> updateEntryInFile(DateTime date, JournalEntry entry) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final filePath = getFilePath(normalizedDate);

    if (!await _fileSystemService.fileExists(filePath)) {
      throw Exception('Journal file not found');
    }

    final content = await _fileSystemService.readFileAsString(filePath);
    if (content == null) {
      throw Exception('Could not read journal file');
    }

    final newContent = _replaceEntryBlock(content, entry);

    final success = await _fileSystemService.writeFileAsString(filePath, newContent);
    if (!success) {
      throw Exception('Failed to update entry in journal file');
    }

    _log.info('Updated entry in journal (surgical)', data: {
      'date': _formatDate(normalizedDate),
      'id': entry.id,
    });
  }

  /// Delete a specific entry block from the file
  ///
  /// Finds the block by its para:ID and removes only that section.
  /// Everything else in the file is preserved.
  Future<void> deleteEntryFromFile(DateTime date, String entryId) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final filePath = getFilePath(normalizedDate);

    if (!await _fileSystemService.fileExists(filePath)) {
      _log.warn('Journal file not found for delete', data: {'date': _formatDate(normalizedDate)});
      return;
    }

    final content = await _fileSystemService.readFileAsString(filePath);
    if (content == null) {
      throw Exception('Could not read journal file');
    }

    final newContent = _removeEntryBlock(content, entryId);

    final success = await _fileSystemService.writeFileAsString(filePath, newContent);
    if (!success) {
      throw Exception('Failed to delete entry from journal file');
    }

    _log.info('Deleted entry from journal (surgical)', data: {
      'date': _formatDate(normalizedDate),
      'id': entryId,
    });
  }

  /// Create a new file with frontmatter and one entry
  String _createNewFileWithEntry(DateTime date, JournalEntry entry, String? audioPath) {
    final buffer = StringBuffer();

    // Frontmatter
    buffer.writeln('---');
    buffer.writeln('date: ${_formatDate(date)}');
    if (audioPath != null) {
      buffer.writeln('assets:');
      buffer.writeln('  ${entry.id}: $audioPath');
    }
    buffer.writeln('---');
    buffer.writeln();

    // Entry
    buffer.writeln(_serializeEntry(entry));

    return buffer.toString();
  }

  /// Append an entry to existing file content
  String _appendEntryToContent(String content, JournalEntry entry, String? audioPath) {
    // If we have an audio path, we need to update the frontmatter
    if (audioPath != null) {
      content = _addAssetToFrontmatter(content, entry.id, audioPath);
    }

    // Ensure there's a newline at the end before appending
    if (!content.endsWith('\n')) {
      content += '\n';
    }
    if (!content.endsWith('\n\n')) {
      content += '\n';
    }

    // Append the new entry
    content += _serializeEntry(entry);
    content += '\n';

    return content;
  }

  /// Add an asset mapping to the frontmatter
  String _addAssetToFrontmatter(String content, String id, String path) {
    final parts = _splitFrontmatter(content);
    final frontmatter = parts.$1;
    final body = parts.$2;

    if (frontmatter.isEmpty) {
      // No frontmatter - create one
      final buffer = StringBuffer();
      buffer.writeln('---');
      buffer.writeln('assets:');
      buffer.writeln('  $id: $path');
      buffer.writeln('---');
      buffer.writeln();
      buffer.write(body);
      return buffer.toString();
    }

    // Has frontmatter - check if assets section exists
    final lines = frontmatter.split('\n');
    final buffer = StringBuffer();
    buffer.writeln('---');

    bool hasAssets = lines.any((l) => l.trim().startsWith('assets:'));
    bool addedAsset = false;

    for (final line in lines) {
      buffer.writeln(line);

      // Add new asset right after "assets:" line
      if (line.trim() == 'assets:' && !addedAsset) {
        buffer.writeln('  $id: $path');
        addedAsset = true;
      }
    }

    // If no assets section existed, add it
    if (!hasAssets) {
      buffer.writeln('assets:');
      buffer.writeln('  $id: $path');
    }

    buffer.writeln('---');
    buffer.writeln();
    buffer.write(body);

    return buffer.toString();
  }

  /// Find and replace a specific entry block in the content
  String _replaceEntryBlock(String content, JournalEntry entry) {
    final blockRange = _findEntryBlockRange(content, entry.id);
    if (blockRange == null) {
      _log.warn('Entry block not found for replacement', data: {'id': entry.id});
      // Fall back to appending
      return _appendEntryToContent(content, entry, entry.audioPath);
    }

    final before = content.substring(0, blockRange.$1);
    final after = content.substring(blockRange.$2);

    // Build new block
    final newBlock = '${_serializeEntry(entry)}\n';

    return '$before$newBlock$after';
  }

  /// Find and remove a specific entry block from the content
  String _removeEntryBlock(String content, String entryId) {
    final blockRange = _findEntryBlockRange(content, entryId);
    if (blockRange == null) {
      _log.warn('Entry block not found for deletion', data: {'id': entryId});
      return content;
    }

    final before = content.substring(0, blockRange.$1);
    final after = content.substring(blockRange.$2);

    // Also remove the asset from frontmatter
    var result = before + after;
    result = _removeAssetFromFrontmatter(result, entryId);

    // Clean up excessive newlines
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result;
  }

  /// Find the start and end position of an entry block by its ID
  /// Returns (startIndex, endIndex) or null if not found
  (int, int)? _findEntryBlockRange(String content, String entryId) {
    // Look for "# para:ID" pattern
    final headerPattern = RegExp(r'^# para:' + RegExp.escape(entryId) + r'[ \t]', multiLine: true);
    final match = headerPattern.firstMatch(content);

    if (match == null) {
      return null;
    }

    final startIndex = match.start;

    // Find the end - next H1 or end of file
    // Look for any line starting with "# " after this block
    final afterStart = content.substring(match.end);
    final nextH1 = RegExp(r'^# ', multiLine: true).firstMatch(afterStart);

    int endIndex;
    if (nextH1 != null) {
      endIndex = match.end + nextH1.start;
    } else {
      endIndex = content.length;
    }

    return (startIndex, endIndex);
  }

  /// Remove an asset mapping from the frontmatter
  String _removeAssetFromFrontmatter(String content, String id) {
    // Simple approach: remove the line "  id: path"
    final pattern = RegExp(r'^\s*' + RegExp.escape(id) + r':.*\n?', multiLine: true);
    return content.replaceAll(pattern, '');
  }

  /// List all available journal dates (most recent first)
  Future<List<DateTime>> listJournalDates() async {
    await ensureDirectoryExists();

    final files = await _fileSystemService.listDirectory(journalsPath);
    final dates = <DateTime>[];

    for (final filePath in files) {
      if (filePath.endsWith('.md')) {
        final filename = filePath.split('/').last;
        final dateStr = filename.replaceAll('.md', '');
        final date = _parseDate(dateStr);
        if (date != null) {
          dates.add(date);
        }
      }
    }

    dates.sort((a, b) => b.compareTo(a)); // Most recent first
    return dates;
  }

  // ============================================================
  // Parsing
  // ============================================================

  JournalDay _parseJournalFile(String content, DateTime date) {
    final parts = _splitFrontmatter(content);
    final frontmatter = parts.$1;
    final body = parts.$2;

    // Parse frontmatter
    Map<String, String> assets = {};
    if (frontmatter.isNotEmpty) {
      try {
        final yaml = loadYaml(frontmatter);
        if (yaml is Map && yaml['assets'] is Map) {
          assets = Map<String, String>.from(
            (yaml['assets'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
          );
        }
      } catch (e) {
        _log.warn('Failed to parse frontmatter', data: {'error': e.toString()});
      }
    }

    // Parse entries
    final entries = _parseEntries(body, assets);

    return JournalDay(
      date: date,
      entries: entries,
      assets: assets,
      filePath: '$_journalFolderName/${_formatDate(date)}.md',
    );
  }

  (String, String) _splitFrontmatter(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('---')) {
      return ('', trimmed);
    }

    final endIndex = trimmed.indexOf('---', 3);
    if (endIndex == -1) {
      return ('', trimmed);
    }

    final frontmatter = trimmed.substring(3, endIndex).trim();
    final body = trimmed.substring(endIndex + 3).trim();
    return (frontmatter, body);
  }

  List<JournalEntry> _parseEntries(String body, Map<String, String> assets) {
    if (body.isEmpty) return [];

    final entries = <JournalEntry>[];
    final lines = body.split('\n');

    String? currentId;
    String? currentTitle;
    bool isPlainH1 = false;
    final contentBuffer = StringBuffer();
    int plainEntryCounter = 0;
    bool hasPreamble = false; // Track if we have preamble content before first H1

    _log.debug('Parsing journal body', data: {'lines': lines.length, 'bodyPreview': body.substring(0, body.length > 200 ? 200 : body.length)});

    for (final line in lines) {
      final trimmedLine = line.trim();

      // Check for para:ID format first
      final paraId = ParaIdService.parseFromH1(trimmedLine);

      if (paraId != null) {
        // Save previous entry if exists
        if (currentId != null) {
          entries.add(_createEntry(
            id: currentId,
            title: currentTitle ?? '',
            content: contentBuffer.toString().trim(),
            audioPath: assets[currentId],
            isPlainMarkdown: isPlainH1,
          ));
        } else if (hasPreamble && contentBuffer.toString().trim().isNotEmpty) {
          // Save preamble content before this para: H1
          final preambleContent = contentBuffer.toString().trim();
          _log.debug('Saving preamble before para:H1', data: {'contentLength': preambleContent.length});
          entries.add(_createEntry(
            id: 'preamble',
            title: '',
            content: preambleContent,
            audioPath: null,
            isPlainMarkdown: true,
          ));
        }

        // Start new para entry
        currentId = paraId;
        currentTitle = ParaIdService.parseTitleFromH1(trimmedLine);
        isPlainH1 = false;
        contentBuffer.clear();
      } else if (trimmedLine.startsWith('# ')) {
        // Plain H1 without para:ID
        // Save previous entry if exists
        if (currentId != null) {
          entries.add(_createEntry(
            id: currentId,
            title: currentTitle ?? '',
            content: contentBuffer.toString().trim(),
            audioPath: assets[currentId],
            isPlainMarkdown: isPlainH1,
          ));
        } else if (hasPreamble && contentBuffer.toString().trim().isNotEmpty) {
          // Save preamble content before this plain H1
          final preambleContent = contentBuffer.toString().trim();
          _log.debug('Saving preamble before plain H1', data: {'contentLength': preambleContent.length});
          entries.add(_createEntry(
            id: 'preamble',
            title: '',
            content: preambleContent,
            audioPath: null,
            isPlainMarkdown: true,
          ));
        }

        // Start new plain entry with generated ID
        plainEntryCounter++;
        currentId = 'plain_$plainEntryCounter';
        currentTitle = trimmedLine.substring(2).trim(); // Remove "# "
        isPlainH1 = true;
        contentBuffer.clear();
      } else if (currentId != null) {
        // Add to current entry's content
        contentBuffer.writeln(line);
      } else {
        // Content before any H1 - accumulate as preamble
        // Preserve all lines (including blank) for preamble formatting
        contentBuffer.writeln(line);
        if (trimmedLine.isNotEmpty) {
          hasPreamble = true;
        }
      }
    }

    // Handle content before any H1 (preamble) - only if no H1 was ever found
    if (currentId == null && contentBuffer.toString().trim().isNotEmpty) {
      entries.add(_createEntry(
        id: 'preamble',
        title: '',
        content: contentBuffer.toString().trim(),
        audioPath: null,
        isPlainMarkdown: true,
      ));
    }

    // Don't forget the last entry
    if (currentId != null) {
      entries.add(_createEntry(
        id: currentId,
        title: currentTitle ?? '',
        content: contentBuffer.toString().trim(),
        audioPath: assets[currentId],
        isPlainMarkdown: isPlainH1,
      ));
    }

    _log.debug('Parsing complete', data: {
      'entryCount': entries.length,
      'entryIds': entries.map((e) => e.id).toList(),
      'hasPreamble': entries.any((e) => e.id == 'preamble'),
    });

    return entries;
  }

  JournalEntry _createEntry({
    required String id,
    required String title,
    required String content,
    String? audioPath,
    bool isPlainMarkdown = false,
  }) {
    // Detect entry type from content
    final linkedFile = _extractWikilink(content);

    if (linkedFile != null) {
      return JournalEntry(
        id: id,
        title: title,
        content: content,
        type: JournalEntryType.linked,
        createdAt: DateTime.now(),
        linkedFilePath: linkedFile,
        audioPath: audioPath,
        isPlainMarkdown: isPlainMarkdown,
      );
    } else if (audioPath != null) {
      return JournalEntry(
        id: id,
        title: title,
        content: content,
        type: JournalEntryType.voice,
        createdAt: DateTime.now(),
        audioPath: audioPath,
        durationSeconds: 0, // TODO: Could parse from filename or store in frontmatter
        isPlainMarkdown: isPlainMarkdown,
      );
    } else {
      return JournalEntry(
        id: id,
        title: title,
        content: content,
        type: JournalEntryType.text,
        createdAt: DateTime.now(),
        isPlainMarkdown: isPlainMarkdown,
      );
    }
  }

  String? _extractWikilink(String content) {
    // Match [[path]] or [[path|display]]
    final regex = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]');
    final match = regex.firstMatch(content);
    return match?.group(1);
  }

  // ============================================================
  // Serialization
  // ============================================================

  String _serializeJournal(JournalDay journal) {
    final buffer = StringBuffer();

    // Frontmatter
    buffer.writeln('---');
    buffer.writeln('date: ${journal.dateString}');

    if (journal.assets.isNotEmpty) {
      buffer.writeln('assets:');
      for (final entry in journal.assets.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    buffer.writeln('---');
    buffer.writeln();

    // Entries
    for (var i = 0; i < journal.entries.length; i++) {
      final entry = journal.entries[i];
      buffer.writeln(_serializeEntry(entry));

      // Add blank line between entries (but not after last)
      if (i < journal.entries.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  String _serializeEntry(JournalEntry entry) {
    final buffer = StringBuffer();

    // Handle different entry types:
    // 1. Preamble - no H1, just content
    // 2. Plain H1s - preserve without para: prefix
    // 3. Para entries - use para:ID format
    if (entry.id == 'preamble') {
      // Preamble: just content, no header
      if (entry.content.isNotEmpty) {
        buffer.write(entry.content);
      }
    } else if (entry.isPlainMarkdown) {
      // Plain H1: preserve original format without para:
      buffer.writeln('# ${entry.title}');
      buffer.writeln();
      if (entry.content.isNotEmpty) {
        buffer.writeln(entry.content);
      }
    } else {
      // Para entry: use para:ID format
      buffer.writeln(ParaIdService.formatH1(entry.id, entry.title));
      buffer.writeln();

      // Content
      if (entry.isLinked && entry.linkedFilePath != null) {
        buffer.writeln('See [[${entry.linkedFilePath}]]');
      } else if (entry.content.isNotEmpty) {
        buffer.writeln(entry.content);
      }
    }

    // Add horizontal rule after entry (except preamble)
    if (entry.id != 'preamble') {
      buffer.writeln();
      buffer.writeln('---');
    }

    return buffer.toString().trimRight();
  }

  // ============================================================
  // Utilities
  // ============================================================

  static String _formatDate(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static DateTime? _parseDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } catch (_) {
      return null;
    }
  }
}
