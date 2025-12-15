import 'package:flutter/foundation.dart';
import 'journal_entry.dart';

/// A full day's journal containing multiple entries.
///
/// Corresponds to a single markdown file in the journals/ folder.
/// File naming: `journals/2025-12-14.md`
@immutable
class JournalDay {
  /// The date this journal represents
  final DateTime date;

  /// All entries for this day, in chronological order
  final List<JournalEntry> entries;

  /// Asset mappings from frontmatter (para ID -> relative path)
  final Map<String, String> assets;

  /// Path to the journal file (relative to vault)
  final String filePath;

  const JournalDay({
    required this.date,
    required this.entries,
    required this.assets,
    required this.filePath,
  });

  /// Create an empty journal for a date
  factory JournalDay.empty(DateTime date) {
    final dateStr = _formatDate(date);
    return JournalDay(
      date: DateTime(date.year, date.month, date.day),
      entries: const [],
      assets: const {},
      filePath: 'journals/$dateStr.md',
    );
  }

  /// Whether this journal has any entries
  bool get isEmpty => entries.isEmpty;

  /// Whether this journal has entries
  bool get isNotEmpty => entries.isNotEmpty;

  /// Number of entries
  int get entryCount => entries.length;

  /// Date formatted as YYYY-MM-DD
  String get dateString => _formatDate(date);

  /// Date formatted for display (e.g., "Saturday, December 14, 2025")
  String get displayDate {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    final dayName = days[date.weekday - 1];
    final monthName = months[date.month - 1];
    return '$dayName, $monthName ${date.day}, ${date.year}';
  }

  /// Whether this is today's journal
  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Get entry by para ID
  JournalEntry? getEntry(String id) {
    try {
      return entries.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get audio path for an entry
  String? getAudioPath(String entryId) => assets[entryId];

  /// Create a copy with a new entry added
  JournalDay addEntry(JournalEntry entry, {String? audioPath}) {
    final newEntries = [...entries, entry];
    final newAssets = Map<String, String>.from(assets);

    if (audioPath != null) {
      newAssets[entry.id] = audioPath;
    }

    return JournalDay(
      date: date,
      entries: newEntries,
      assets: newAssets,
      filePath: filePath,
    );
  }

  /// Create a copy with an entry updated
  JournalDay updateEntry(JournalEntry entry) {
    final newEntries = entries.map((e) => e.id == entry.id ? entry : e).toList();

    return JournalDay(
      date: date,
      entries: newEntries,
      assets: assets,
      filePath: filePath,
    );
  }

  /// Create a copy with an entry removed
  JournalDay removeEntry(String id) {
    final newEntries = entries.where((e) => e.id != id).toList();
    final newAssets = Map<String, String>.from(assets)..remove(id);

    return JournalDay(
      date: date,
      entries: newEntries,
      assets: newAssets,
      filePath: filePath,
    );
  }

  /// Create a copy with updated fields
  JournalDay copyWith({
    DateTime? date,
    List<JournalEntry>? entries,
    Map<String, String>? assets,
    String? filePath,
  }) {
    return JournalDay(
      date: date ?? this.date,
      entries: entries ?? this.entries,
      assets: assets ?? this.assets,
      filePath: filePath ?? this.filePath,
    );
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is JournalDay && other.dateString == dateString;
  }

  @override
  int get hashCode => dateString.hashCode;

  @override
  String toString() => 'JournalDay($dateString, ${entries.length} entries)';
}
