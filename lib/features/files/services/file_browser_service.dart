import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:docman/docman.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/features/files/models/file_item.dart';

/// Exception thrown when directory listing fails due to permissions
class DirectoryPermissionException implements Exception {
  final String path;
  final String message;

  DirectoryPermissionException(this.path, this.message);

  @override
  String toString() => message;
}

/// Service for browsing the vault folder structure
class FileBrowserService {
  final FileSystemService _fileSystem;
  DocumentFile? _rootDocumentFile; // Cached SAF root for Android
  final Map<String, DocumentFile> _safDirectoryCache = {}; // Cache DocumentFiles by path

  FileBrowserService(this._fileSystem);

  /// Check if we should use SAF for directory access
  bool get _shouldUseSaf => Platform.isAndroid && _fileSystem.getRootUri() != null;

  /// Get or create a DocumentFile for a given path using SAF
  Future<DocumentFile?> _getDocumentFileForPath(String path) async {
    // Check cache first
    if (_safDirectoryCache.containsKey(path)) {
      return _safDirectoryCache[path];
    }

    final rootUri = _fileSystem.getRootUri();
    if (rootUri == null) return null;

    final rootPath = await _fileSystem.getRootPath();

    // If this is the root path, get from persisted permissions
    if (path == rootPath) {
      if (_rootDocumentFile == null) {
        // Get all persisted document permissions
        final persistedDocs = await DocMan.perms.listDocuments(directories: true, files: false);
        debugPrint('[FileBrowserService] Found ${persistedDocs.length} persisted directories');

        // Find the one matching our root URI
        for (final doc in persistedDocs) {
          debugPrint('[FileBrowserService] Checking: ${doc.uri} vs $rootUri');
          if (doc.uri.toString() == rootUri) {
            _rootDocumentFile = doc;
            _safDirectoryCache[path] = doc;
            debugPrint('[FileBrowserService] Found matching root DocumentFile');
            break;
          }
        }
      }
      return _rootDocumentFile;
    }

    // For subfolders, navigate from root
    final relativePath = path.substring(rootPath.length);
    final segments = relativePath.split('/').where((s) => s.isNotEmpty).toList();

    DocumentFile? current = await _getDocumentFileForPath(rootPath);
    for (final segment in segments) {
      if (current == null) return null;

      // Find the child with this name
      final children = await current.listDocuments();
      current = children.where((f) => f.name == segment).firstOrNull;

      if (current != null) {
        final cachePath = '$rootPath/${segments.sublist(0, segments.indexOf(segment) + 1).join('/')}';
        _safDirectoryCache[cachePath] = current;
      }
    }

    return current;
  }

  /// List directory contents using SAF
  Future<List<FileItem>> _listFolderSaf(String path) async {
    final stopwatch = Stopwatch()..start();
    debugPrint('[FileBrowserService] Listing via SAF: $path');

    final docFile = await _getDocumentFileForPath(path);
    debugPrint('[FileBrowserService] Got DocumentFile in ${stopwatch.elapsedMilliseconds}ms');

    if (docFile == null) {
      debugPrint('[FileBrowserService] Could not get DocumentFile for $path');
      return [];
    }

    try {
      // Use stream for better performance with large directories
      final items = <FileItem>[];
      int totalCount = 0;

      await for (final child in docFile.listDocumentsStream()) {
        totalCount++;
        // Skip hidden files and files without names
        final name = child.name;
        if (name.isEmpty || name.startsWith('.')) continue;

        // Convert lastModified (milliseconds since epoch) to DateTime if available
        DateTime? modified;
        final lastMod = child.lastModified;
        if (lastMod > 0) {
          modified = DateTime.fromMillisecondsSinceEpoch(lastMod);
        }

        items.add(FileItem(
          name: name,
          path: '$path/$name',
          type: child.isDirectory == true
              ? FileItemType.folder
              : _getFileType(name),
          modified: modified,
          sizeBytes: child.isDirectory == true ? null : child.size,
        ));
      }

      debugPrint('[FileBrowserService] SAF streamed $totalCount items in ${stopwatch.elapsedMilliseconds}ms');

      // Sort: folders first, then alphabetically
      items.sort((a, b) {
        if (a.isFolder && !b.isFolder) return -1;
        if (!a.isFolder && b.isFolder) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      debugPrint('[FileBrowserService] SAF listed ${items.length} visible items (total: ${stopwatch.elapsedMilliseconds}ms)');
      return items;
    } catch (e) {
      debugPrint('[FileBrowserService] SAF listing error: $e');
      return [];
    }
  }

  /// Get FileItemType from filename
  FileItemType _getFileType(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'md':
      case 'markdown':
        return FileItemType.markdown;
      case 'wav':
      case 'mp3':
      case 'opus':
      case 'm4a':
      case 'aac':
        return FileItemType.audio;
      default:
        return FileItemType.other;
    }
  }

  /// Get the initial path (vault root)
  Future<String> getInitialPath() async {
    return _fileSystem.getRootPath();
  }

  /// Check if the given path is the vault root
  Future<bool> isAtRoot(String path) async {
    final rootPath = await _fileSystem.getRootPath();
    return path == rootPath;
  }

  /// Get the parent path of the given path
  String getParentPath(String path) {
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash <= 0) return '/';
    return path.substring(0, lastSlash);
  }

  /// Get a display-friendly version of the path
  Future<String> getDisplayPath(String path) async {
    final rootPath = await _fileSystem.getRootPath();

    if (path == rootPath) {
      return await _fileSystem.getRootPathDisplay();
    }

    // Show path relative to root with ~ prefix
    final rootDisplay = await _fileSystem.getRootPathDisplay();
    if (path.startsWith(rootPath)) {
      return rootDisplay + path.substring(rootPath.length);
    }

    return path;
  }

  /// Get the folder name from a path
  String getFolderName(String path) {
    return path.split('/').last;
  }

  /// List contents of a folder
  /// Returns items sorted: folders first, then files, alphabetically
  Future<List<FileItem>> listFolder(String path) async {
    // On Android with SAF URI, use SAF to list directories
    if (_shouldUseSaf) {
      debugPrint('[FileBrowserService] Using SAF for path: $path');
      final items = await _listFolderSaf(path);
      if (items.isNotEmpty) {
        return items;
      }
      // If SAF returns empty, try dart:io as fallback (for app's own directories)
      debugPrint('[FileBrowserService] SAF returned empty, trying dart:io fallback');
    }

    // Standard dart:io approach
    try {
      final dir = Directory(path);
      final exists = await dir.exists();
      debugPrint('[FileBrowserService] Directory exists check for $path: $exists');

      if (!exists) {
        debugPrint('[FileBrowserService] Directory does not exist: $path');
        return [];
      }

      final items = <FileItem>[];
      int entityCount = 0;
      int skippedCount = 0;

      try {
        await for (final entity in dir.list()) {
          entityCount++;
          try {
            final stat = await entity.stat();
            final isDirectory = entity is Directory;

            // Skip hidden files/folders (starting with .)
            final name = entity.path.split('/').last;
            if (name.startsWith('.')) {
              skippedCount++;
              continue;
            }

            items.add(FileItem.fromPath(
              entity.path,
              isDirectory: isDirectory,
              modified: stat.modified,
              sizeBytes: isDirectory ? null : stat.size,
            ));
          } catch (e) {
            debugPrint('[FileBrowserService] Error reading ${entity.path}: $e');
          }
        }
      } catch (e) {
        debugPrint('[FileBrowserService] Error iterating directory $path: $e');
      }

      debugPrint('[FileBrowserService] Raw entities: $entityCount, skipped: $skippedCount, visible: ${items.length}');

      // On Android, if directory exists but we can't list contents, it's likely a permission issue
      if (entityCount == 0 && Platform.isAndroid) {
        final rootPath = await _fileSystem.getRootPath();
        // Only show error if this is a subfolder (not root) - root might genuinely be empty
        if (path != rootPath) {
          debugPrint('[FileBrowserService] Android permission issue detected for $path');
          throw DirectoryPermissionException(
            path,
            'Cannot access folder contents on Android.\n\n'
            'To browse this vault, please re-select it in Settings → Storage.\n'
            'This grants the app permission to access subfolders.',
          );
        }
      }

      // Sort: folders first, then alphabetically by name
      items.sort((a, b) {
        if (a.isFolder && !b.isFolder) return -1;
        if (!a.isFolder && b.isFolder) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      debugPrint('[FileBrowserService] Listed ${items.length} items in $path');
      return items;
    } on DirectoryPermissionException {
      rethrow; // Let permission exceptions propagate to show user-friendly message
    } catch (e, stackTrace) {
      debugPrint('[FileBrowserService] Error listing folder $path: $e');
      debugPrint('[FileBrowserService] Stack trace: $stackTrace');
      return [];
    }
  }

  /// Check if a path is within the vault
  Future<bool> isWithinVault(String path) async {
    final rootPath = await _fileSystem.getRootPath();
    return path.startsWith(rootPath);
  }

  /// Read file contents as string (for markdown viewing)
  Future<String?> readFileAsString(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[FileBrowserService] File does not exist: $path');
        return null;
      }
      return await file.readAsString();
    } catch (e) {
      debugPrint('[FileBrowserService] Error reading file $path: $e');
      return null;
    }
  }
}
