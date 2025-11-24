import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/models/relevant_note.dart';
import 'package:app/core/providers/api_provider.dart';
import 'package:flutter/services.dart';

/// Provider for note content with space context
final noteContentProvider =
    FutureProvider.family<
      NoteWithContext,
      ({String spaceId, String captureId})
    >((ref, params) async {
      final apiClient = ref.read(apiClientProvider);
      return apiClient.getNoteContent(params.spaceId, params.captureId);
    });

class NoteWithContextScreen extends ConsumerWidget {
  final String spaceId;
  final RelevantNote note;

  const NoteWithContextScreen({
    super.key,
    required this.spaceId,
    required this.note,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(
      noteContentProvider((spaceId: spaceId, captureId: note.captureId)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(note.filename),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy content',
            onPressed: () => _copyContent(context, contentAsync),
          ),
        ],
      ),
      body: contentAsync.when(
        data: (noteWithContext) => _buildContent(context, noteWithContext),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('Error loading note: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(
                      noteContentProvider((
                        spaceId: spaceId,
                        captureId: note.captureId,
                      )),
                    );
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, NoteWithContext noteWithContext) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Space-specific context section
        if (noteWithContext.spaceContext.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Space Context',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  noteWithContext.spaceContext,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (noteWithContext.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: noteWithContext.tags
                        .map(
                          (tag) => Chip(
                            label: Text(tag),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Note content section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.description,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Note Content',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                noteWithContext.content,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ],
          ),
        ),

        // Metadata section
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetadataRow(
                context,
                Icons.calendar_today,
                'Linked',
                noteWithContext.linkedAt.toString().split('.')[0],
              ),
              if (noteWithContext.lastReferenced != null) ...[
                const SizedBox(height: 8),
                _buildMetadataRow(
                  context,
                  Icons.history,
                  'Last Referenced',
                  noteWithContext.lastReferenced.toString().split('.')[0],
                ),
              ],
              const SizedBox(height: 8),
              _buildMetadataRow(
                context,
                Icons.insert_drive_file,
                'Path',
                noteWithContext.notePath,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _copyContent(
    BuildContext context,
    AsyncValue<NoteWithContext> contentAsync,
  ) {
    contentAsync.whenData((noteWithContext) {
      Clipboard.setData(ClipboardData(text: noteWithContext.content));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content copied to clipboard')),
      );
    });
  }
}
