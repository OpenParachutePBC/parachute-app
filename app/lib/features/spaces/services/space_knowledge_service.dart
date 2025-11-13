import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../core/services/file_system_service.dart';

/// Service for managing knowledge links between captures and spaces
///
/// Each space has its own space.sqlite database with:
/// - relevant_notes: Links captures to this space with context and metadata
/// - Tags, context, and space-specific interpretation
///
/// Philosophy: Captures are canonical (in ~/Parachute/captures/), spaces
/// just reference them with their own context and organization.
class SpaceKnowledgeService {
  final FileSystemService _fileSystemService;
  final Uuid _uuid = const Uuid();

  // Cache of open databases (space_id -> Database)
  final Map<String, Database> _databaseCache = {};

  SpaceKnowledgeService({FileSystemService? fileSystemService})
    : _fileSystemService = fileSystemService ?? FileSystemService();

  /// Get or open the database for a specific space
  Future<Database> _getDatabase(String spacePath) async {
    // Check cache first
    if (_databaseCache.containsKey(spacePath)) {
      return _databaseCache[spacePath]!;
    }

    final dbPath = p.join(spacePath, 'space.sqlite');

    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );

    _databaseCache[spacePath] = db;
    return db;
  }

  /// Create database schema
  Future<void> _createDatabase(Database db, int version) async {
    debugPrint('[SpaceKnowledge] Creating database schema v$version');

    // Metadata table
    await db.execute('''
      CREATE TABLE space_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Insert initial metadata
    await db.insert('space_metadata', {'key': 'schema_version', 'value': '1'});
    await db.insert('space_metadata', {
      'key': 'created_at',
      'value': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    // Core table: Links captures to this space
    await db.execute('''
      CREATE TABLE relevant_notes (
        id TEXT PRIMARY KEY,
        capture_id TEXT NOT NULL,
        note_path TEXT NOT NULL,
        linked_at INTEGER NOT NULL,
        context TEXT,
        tags TEXT,
        last_referenced INTEGER,
        metadata TEXT,
        UNIQUE(capture_id)
      )
    ''');

    // Indexes for performance
    await db.execute('''
      CREATE INDEX idx_linked_at ON relevant_notes(linked_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_last_referenced ON relevant_notes(last_referenced DESC)
    ''');

    debugPrint('[SpaceKnowledge] Database schema created');
  }

  /// Handle database upgrades
  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    debugPrint(
      '[SpaceKnowledge] Upgrading database from v$oldVersion to v$newVersion',
    );
    // Future schema migrations go here
  }

  /// Link a capture to a space
  Future<void> linkCaptureToSpace({
    required String spaceId,
    required String spacePath,
    required String captureId,
    required String notePath,
    String? context,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await _getDatabase(spacePath);
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert('relevant_notes', {
        'id': _uuid.v4(),
        'capture_id': captureId,
        'note_path': notePath,
        'linked_at': now,
        'context': context,
        'tags': tags != null ? jsonEncode(tags) : null,
        'last_referenced': now,
        'metadata': metadata != null ? jsonEncode(metadata) : null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      debugPrint(
        '[SpaceKnowledge] Linked capture $captureId to space $spaceId',
      );
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error linking capture: $e');
      rethrow;
    }
  }

  /// Unlink a capture from a space
  Future<void> unlinkCaptureFromSpace({
    required String spacePath,
    required String captureId,
  }) async {
    try {
      final db = await _getDatabase(spacePath);
      await db.delete(
        'relevant_notes',
        where: 'capture_id = ?',
        whereArgs: [captureId],
      );

      debugPrint('[SpaceKnowledge] Unlinked capture $captureId');
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error unlinking capture: $e');
      rethrow;
    }
  }

  /// Update context for a linked capture
  Future<void> updateCaptureContext({
    required String spacePath,
    required String captureId,
    String? context,
    List<String>? tags,
  }) async {
    try {
      final db = await _getDatabase(spacePath);
      final updates = <String, dynamic>{
        'last_referenced': DateTime.now().millisecondsSinceEpoch,
      };

      if (context != null) {
        updates['context'] = context;
      }
      if (tags != null) {
        updates['tags'] = jsonEncode(tags);
      }

      await db.update(
        'relevant_notes',
        updates,
        where: 'capture_id = ?',
        whereArgs: [captureId],
      );

      debugPrint('[SpaceKnowledge] Updated capture $captureId context');
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error updating capture context: $e');
      rethrow;
    }
  }

  /// Get all captures linked to a space
  Future<List<LinkedCapture>> getLinkedCaptures({
    required String spacePath,
    int? limit,
    int? offset,
  }) async {
    try {
      final db = await _getDatabase(spacePath);

      final results = await db.query(
        'relevant_notes',
        orderBy: 'linked_at DESC',
        limit: limit,
        offset: offset,
      );

      return results.map((row) => LinkedCapture.fromMap(row)).toList();
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error getting linked captures: $e');
      return [];
    }
  }

  /// Check if a capture is linked to a space
  Future<bool> isCaptureLinked({
    required String spacePath,
    required String captureId,
  }) async {
    try {
      final db = await _getDatabase(spacePath);

      final results = await db.query(
        'relevant_notes',
        where: 'capture_id = ?',
        whereArgs: [captureId],
        limit: 1,
      );

      return results.isNotEmpty;
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error checking if capture linked: $e');
      return false;
    }
  }

  /// Get linked capture details
  Future<LinkedCapture?> getLinkedCapture({
    required String spacePath,
    required String captureId,
  }) async {
    try {
      final db = await _getDatabase(spacePath);

      final results = await db.query(
        'relevant_notes',
        where: 'capture_id = ?',
        whereArgs: [captureId],
        limit: 1,
      );

      if (results.isEmpty) return null;
      return LinkedCapture.fromMap(results.first);
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error getting linked capture: $e');
      return null;
    }
  }

  /// Get statistics for a space
  Future<SpaceStats> getSpaceStats({required String spacePath}) async {
    try {
      final db = await _getDatabase(spacePath);

      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM relevant_notes',
      );
      final count = Sqflite.firstIntValue(countResult) ?? 0;

      final lastReferencedResult = await db.query(
        'relevant_notes',
        columns: ['last_referenced'],
        orderBy: 'last_referenced DESC',
        limit: 1,
      );

      DateTime? lastReferenced;
      if (lastReferencedResult.isNotEmpty) {
        final timestamp = lastReferencedResult.first['last_referenced'] as int?;
        if (timestamp != null) {
          lastReferenced = DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      }

      return SpaceStats(noteCount: count, lastReferenced: lastReferenced);
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error getting space stats: $e');
      return SpaceStats(noteCount: 0);
    }
  }

  /// Search captures by tags
  Future<List<LinkedCapture>> searchByTags({
    required String spacePath,
    required List<String> tags,
  }) async {
    try {
      final db = await _getDatabase(spacePath);

      // Build WHERE clause for tag matching
      final conditions = tags
          .map((tag) => "tags LIKE '%\"$tag\"%'")
          .join(' OR ');

      final results = await db.query(
        'relevant_notes',
        where: conditions,
        orderBy: 'linked_at DESC',
      );

      return results.map((row) => LinkedCapture.fromMap(row)).toList();
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error searching by tags: $e');
      return [];
    }
  }

  /// Close database for a space (cleanup)
  Future<void> closeDatabaseForSpace(String spacePath) async {
    if (_databaseCache.containsKey(spacePath)) {
      await _databaseCache[spacePath]!.close();
      _databaseCache.remove(spacePath);
      debugPrint('[SpaceKnowledge] Closed database for $spacePath');
    }
  }

  /// Close all databases
  Future<void> closeAll() async {
    for (final db in _databaseCache.values) {
      await db.close();
    }
    _databaseCache.clear();
    debugPrint('[SpaceKnowledge] Closed all databases');
  }
}

/// Represents a capture linked to a space
class LinkedCapture {
  final String id;
  final String captureId;
  final String notePath;
  final DateTime linkedAt;
  final String? context;
  final List<String>? tags;
  final DateTime? lastReferenced;
  final Map<String, dynamic>? metadata;

  LinkedCapture({
    required this.id,
    required this.captureId,
    required this.notePath,
    required this.linkedAt,
    this.context,
    this.tags,
    this.lastReferenced,
    this.metadata,
  });

  factory LinkedCapture.fromMap(Map<String, dynamic> map) {
    return LinkedCapture(
      id: map['id'] as String,
      captureId: map['capture_id'] as String,
      notePath: map['note_path'] as String,
      linkedAt: DateTime.fromMillisecondsSinceEpoch(map['linked_at'] as int),
      context: map['context'] as String?,
      tags: map['tags'] != null
          ? List<String>.from(jsonDecode(map['tags'] as String) as List)
          : null,
      lastReferenced: map['last_referenced'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_referenced'] as int)
          : null,
      metadata: map['metadata'] != null
          ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'capture_id': captureId,
      'note_path': notePath,
      'linked_at': linkedAt.millisecondsSinceEpoch,
      'context': context,
      'tags': tags != null ? jsonEncode(tags) : null,
      'last_referenced': lastReferenced?.millisecondsSinceEpoch,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    };
  }
}

/// Space statistics
class SpaceStats {
  final int noteCount;
  final DateTime? lastReferenced;

  SpaceStats({required this.noteCount, this.lastReferenced});
}
