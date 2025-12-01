import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/models/space.dart';
import '../providers/space_knowledge_provider.dart';
import '../services/space_knowledge_service.dart';
import '../../../features/files/providers/local_file_browser_provider.dart';
import '../../recorder/screens/recording_detail_screen.dart';
import '../../recorder/services/storage_service.dart';
import '../../recorder/models/recording.dart';

/// Space detail screen showing all linked captures
class SpaceDetailScreen extends ConsumerStatefulWidget {
  final Space space;

  const SpaceDetailScreen({super.key, required this.space});

  @override
  ConsumerState<SpaceDetailScreen> createState() => _SpaceDetailScreenState();
}

class _SpaceDetailScreenState extends ConsumerState<SpaceDetailScreen> {
  String _searchQuery = '';
  final List<String> _selectedTags = [];
  final String _sortBy = 'recent'; // 'recent', 'referenced', 'alphabetical'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (widget.space.icon?.isNotEmpty ?? false) ...[
              Text(widget.space.icon!, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(widget.space.name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(),
            tooltip: 'Search',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(),
            tooltip: 'Filter',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'cleanup') {
                _cleanupOrphanedLinks();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'cleanup',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services),
                    SizedBox(width: 8),
                    Text('Clean up broken links'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          _buildStatsBar(),

          // Active filters
          if (_selectedTags.isNotEmpty || _searchQuery.isNotEmpty)
            _buildActiveFilters(),

          // Linked captures list
          Expanded(child: _buildLinkedCapturesList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToRecorder(),
        icon: const Icon(Icons.add),
        label: const Text('New Capture'),
      ),
    );
  }

  Widget _buildStatsBar() {
    return FutureBuilder<String>(
      future: _getSpacePath(),
      builder: (context, pathSnapshot) {
        if (!pathSnapshot.hasData) {
          return const SizedBox.shrink();
        }

        final spacePath = pathSnapshot.data!;
        final statsAsync = ref.watch(spaceStatsProvider(spacePath));

        return statsAsync.when(
          data: (stats) {
            return Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.note,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${stats.noteCount} ${stats.noteCount == 1 ? 'capture' : 'captures'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (stats.lastReferenced != null) ...[
                    const Spacer(),
                    Text(
                      'Last used ${_formatDate(stats.lastReferenced!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_searchQuery.isNotEmpty)
            Chip(
              label: Text('Search: $_searchQuery'),
              onDeleted: () => setState(() => _searchQuery = ''),
            ),
          ..._selectedTags.map(
            (tag) => Chip(
              label: Text('#$tag'),
              onDeleted: () => setState(() => _selectedTags.remove(tag)),
            ),
          ),
          if (_selectedTags.isNotEmpty || _searchQuery.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _searchQuery = '';
                _selectedTags.clear();
              }),
              child: const Text('Clear all'),
            ),
        ],
      ),
    );
  }

  Widget _buildLinkedCapturesList() {
    return FutureBuilder<String>(
      future: _getSpacePath(),
      builder: (context, pathSnapshot) {
        if (!pathSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final spacePath = pathSnapshot.data!;
        final linkedCapturesAsync = ref.watch(
          spaceLinkedCapturesProvider(spacePath),
        );

        return linkedCapturesAsync.when(
          data: (linkedCaptures) {
            if (linkedCaptures.isEmpty) {
              return _buildEmptyState();
            }

            // Apply filters
            var filteredCaptures = linkedCaptures;

            if (_selectedTags.isNotEmpty) {
              filteredCaptures = filteredCaptures.where((capture) {
                final captureTags = capture.tags ?? [];
                return _selectedTags.any((tag) => captureTags.contains(tag));
              }).toList();
            }

            // Apply sorting
            switch (_sortBy) {
              case 'recent':
                filteredCaptures.sort(
                  (a, b) => b.linkedAt.compareTo(a.linkedAt),
                );
                break;
              case 'referenced':
                filteredCaptures.sort((a, b) {
                  final aTime = a.lastReferenced ?? a.linkedAt;
                  final bTime = b.lastReferenced ?? b.linkedAt;
                  return bTime.compareTo(aTime);
                });
                break;
            }

            return ListView.builder(
              itemCount: filteredCaptures.length,
              itemBuilder: (context, index) {
                final linkedCapture = filteredCaptures[index];
                return _buildCaptureCard(linkedCapture, spacePath);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) =>
              Center(child: Text('Error loading captures: $error')),
        );
      },
    );
  }

  Widget _buildCaptureCard(LinkedCapture linkedCapture, String spacePath) {
    return FutureBuilder<Recording?>(
      future: _loadRecording(linkedCapture.captureId),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final recording = snapshot.data;
        final isOrphaned = !isLoading && recording == null;

        // Show orphaned state with option to remove
        if (isOrphaned) {
          return _buildOrphanedCaptureCard(linkedCapture, spacePath);
        }

        final title = isLoading ? 'Loading...' : (recording?.title ?? 'Untitled');
        final timestamp = recording?.timestamp;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: InkWell(
            onTap: () => _openRecording(linkedCapture.captureId),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and date
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (timestamp != null)
                        Text(
                          _formatDate(timestamp),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),

                  // Space-specific context
                  if (linkedCapture.context?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              linkedCapture.context!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Tags
                  if (linkedCapture.tags?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: linkedCapture.tags!
                          .map(
                            (tag) => Chip(
                              label: Text(
                                '#$tag',
                                style: const TextStyle(fontSize: 12),
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],

                  // Linked date
                  const SizedBox(height: 8),
                  Text(
                    'Linked ${_formatDate(linkedCapture.linkedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No captures linked yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Record a voice note and link it to this space',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _navigateToRecorder(),
              icon: const Icon(Icons.mic),
              label: const Text('Start Recording'),
            ),
          ],
        ),
      ),
    );
  }

  /// Card shown for orphaned links (recording was deleted)
  Widget _buildOrphanedCaptureCard(
    LinkedCapture linkedCapture,
    String spacePath,
  ) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.link_off,
                  color: theme.colorScheme.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recording deleted',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _unlinkCapture(linkedCapture, spacePath),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Remove',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${linkedCapture.captureId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.7),
                fontFamily: 'monospace',
              ),
            ),
            if (linkedCapture.context?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                'Context: ${linkedCapture.context}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Linked ${_formatDate(linkedCapture.linkedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Remove an orphaned link from this sphere
  Future<void> _unlinkCapture(
    LinkedCapture linkedCapture,
    String spacePath,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Link?'),
        content: const Text(
          'This will remove the orphaned link from this sphere. '
          'The original recording has already been deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final knowledgeService = ref.read(spaceKnowledgeServiceProvider);
      await knowledgeService.unlinkCaptureFromSpace(
        spacePath: spacePath,
        captureId: linkedCapture.captureId,
      );

      // Refresh the list
      ref.invalidate(spaceLinkedCapturesProvider(spacePath));
      ref.invalidate(spaceStatsProvider(spacePath));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove link: $e')),
        );
      }
    }
  }

  /// Clean up all orphaned links in this sphere
  Future<void> _cleanupOrphanedLinks() async {
    final spacePath = await _getSpacePath();
    final knowledgeService = ref.read(spaceKnowledgeServiceProvider);
    final linkedCaptures = await knowledgeService.getLinkedCaptures(
      spacePath: spacePath,
    );

    // Find orphaned links
    final orphanedLinks = <LinkedCapture>[];
    for (final link in linkedCaptures) {
      final recording = await _loadRecording(link.captureId);
      if (recording == null) {
        orphanedLinks.add(link);
      }
    }

    if (orphanedLinks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No broken links found')),
        );
      }
      return;
    }

    // Confirm cleanup
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clean Up Broken Links?'),
        content: Text(
          'Found ${orphanedLinks.length} broken ${orphanedLinks.length == 1 ? 'link' : 'links'} '
          'to deleted recordings. Remove them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clean Up'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Remove all orphaned links
    int removed = 0;
    for (final link in orphanedLinks) {
      try {
        await knowledgeService.unlinkCaptureFromSpace(
          spacePath: spacePath,
          captureId: link.captureId,
        );
        removed++;
      } catch (e) {
        debugPrint('[SpaceDetail] Failed to remove orphaned link: $e');
      }
    }

    // Refresh the list
    ref.invalidate(spaceLinkedCapturesProvider(spacePath));
    ref.invalidate(spaceStatsProvider(spacePath));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed $removed broken ${removed == 1 ? 'link' : 'links'}',
          ),
        ),
      );
    }
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String query = _searchQuery;
        return AlertDialog(
          title: const Text('Search Captures'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter search term...',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => query = value,
            onSubmitted: (value) {
              setState(() => _searchQuery = value);
              Navigator.pop(context);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => _searchQuery = query);
                Navigator.pop(context);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  void _showFilterDialog() {
    // TODO: Implement tag filter dialog
    // For now, just show a placeholder
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Tag filtering coming soon')));
  }

  Future<String> _getSpacePath() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);
    final spacesPath = await fileSystemService.getSpacesPath();
    return p.join(spacesPath, widget.space.path);
  }

  Future<Recording?> _loadRecording(String captureId) async {
    try {
      final storageService = StorageService();

      // Load all recordings and find by ID
      final recordings = await storageService.getRecordings();
      return recordings.where((r) => r.id == captureId).firstOrNull;
    } catch (e) {
      debugPrint('[SpaceDetail] Error loading recording: $e');
      return null;
    }
  }

  void _openRecording(String captureId) async {
    final recording = await _loadRecording(captureId);
    if (recording != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RecordingDetailScreen(recording: recording),
        ),
      );
    }
  }

  void _navigateToRecorder() {
    // Navigate to recorder tab
    // This will depend on your main navigation structure
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
