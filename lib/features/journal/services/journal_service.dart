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
class JournalService {
  final String _vaultPath;
  final String _journalFolderName;
  final ParaIdService _paraIdService;
  final _log = logger.createLogger('JournalService');

  JournalService({
    required String vaultPath,
    required String journalFolderName,
    required ParaIdService paraIdService,
  })  : _vaultPath = vaultPath,
        _journalFolderName = journalFolderName,
        _paraIdService = paraIdService;

  /// Factory constructor that uses FileSystemService for configuration
  static Future<JournalService> create({
    required FileSystemService fileSystemService,
    required ParaIdService paraIdService,
  }) async {
    final vaultPath = await fileSystemService.getRootPath();
    final journalFolderName = fileSystemService.getJournalFolderName();
    return JournalService(
      vaultPath: vaultPath,
      journalFolderName: journalFolderName,
      paraIdService: paraIdService,
    );
  }

  /// Path to journals directory
  String get journalsPath => '$_vaultPath/$_journalFolderName';

  /// Ensure journals directory exists
  Future<void> ensureDirectoryExists() async {
    final dir = Directory(journalsPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      _log.info('Created journals directory');
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
    final file = File(filePath);

    if (!await file.exists()) {
      _log.debug('Journal file not found, returning empty', data: {'date': _formatDate(normalizedDate)});
      return JournalDay.empty(normalizedDate);
    }

    try {
      final content = await file.readAsString();
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
      final file = File(filePath);
      await file.writeAsString(content);
      _log.debug('Saved journal', data: {
        'date': journal.dateString,
        'entries': journal.entryCount,
      });
    } catch (e, st) {
      _log.error('Failed to save journal', error: e, stackTrace: st, data: {'date': journal.dateString});
      rethrow;
    }
  }

  /// Add a new entry to a journal day
  ///
  /// Generates a new para ID, creates the entry, and saves the journal.
  Future<JournalEntry> addEntry({
    required DateTime date,
    required String title,
    required String content,
    JournalEntryType type = JournalEntryType.text,
    String? audioPath,
    String? linkedFilePath,
    int? durationSeconds,
  }) async {
    final journal = await loadDay(date);
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

    final updatedJournal = journal.addEntry(entry, audioPath: audioPath);
    await saveDay(updatedJournal);

    _log.info('Added journal entry', data: {
      'date': journal.dateString,
      'id': id,
      'type': type.name,
    });

    return entry;
  }

  /// Add a text entry to today's journal
  Future<JournalEntry> addTextEntry({
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
  Future<JournalEntry> addVoiceEntry({
    required String transcript,
    required String audioPath,
    required int durationSeconds,
    String? title,
  }) async {
    final now = DateTime.now();
    final defaultTitle = _formatTime(now);

    // Copy audio file to journal assets folder
    final assetsDir = Directory('$journalsPath/assets');
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }

    // Generate filename based on timestamp
    final audioFilename = '${_formatDate(now)}_${_formatTime(now).replaceAll(':', '-')}.wav';
    final destPath = '${assetsDir.path}/$audioFilename';
    final relativePath = '$_journalFolderName/assets/$audioFilename';

    // Copy the audio file
    final sourceFile = File(audioPath);
    if (await sourceFile.exists()) {
      await sourceFile.copy(destPath);
      _log.debug('Copied audio file to journal assets', data: {'path': relativePath});

      // Delete the temp file
      try {
        await sourceFile.delete();
      } catch (e) {
        _log.warn('Could not delete temp audio file', data: {'error': e.toString()});
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
  Future<JournalEntry> addLinkedEntry({
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

  /// Update an existing entry
  Future<void> updateEntry(DateTime date, JournalEntry entry) async {
    final journal = await loadDay(date);
    final updatedJournal = journal.updateEntry(entry);
    await saveDay(updatedJournal);

    _log.info('Updated journal entry', data: {
      'date': journal.dateString,
      'id': entry.id,
    });
  }

  /// Delete an entry
  Future<void> deleteEntry(DateTime date, String entryId) async {
    final journal = await loadDay(date);
    final updatedJournal = journal.removeEntry(entryId);
    await saveDay(updatedJournal);

    _log.info('Deleted journal entry', data: {
      'date': journal.dateString,
      'id': entryId,
    });
  }

  /// List all available journal dates (most recent first)
  Future<List<DateTime>> listJournalDates() async {
    await ensureDirectoryExists();

    final dir = Directory(journalsPath);
    final dates = <DateTime>[];

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        final filename = entity.path.split('/').last;
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
        // Content before any H1 - create a "preamble" entry
        if (trimmedLine.isNotEmpty) {
          contentBuffer.writeln(line);
        }
      }
    }

    // Handle content before any H1 (preamble)
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
      return JournalEntry.linked(
        id: id,
        title: title,
        linkedFilePath: linkedFile,
        audioPath: audioPath,
      );
    } else if (audioPath != null) {
      return JournalEntry.voice(
        id: id,
        title: title,
        content: content,
        audioPath: audioPath,
        durationSeconds: 0, // TODO: Could parse from filename or store in frontmatter
      );
    } else {
      return JournalEntry.text(
        id: id,
        title: title,
        content: content,
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

    // H1 with para ID
    buffer.writeln(ParaIdService.formatH1(entry.id, entry.title));
    buffer.writeln();

    // Content
    if (entry.isLinked && entry.linkedFilePath != null) {
      buffer.writeln('See [[${entry.linkedFilePath}]]');
    } else if (entry.content.isNotEmpty) {
      buffer.writeln(entry.content);
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
