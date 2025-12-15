import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../models/journal_entry.dart';

/// Card widget displaying a single journal entry
///
/// Shows the entry title, content preview, and type indicator.
/// The para ID is hidden from the user.
class JournalEntryCard extends StatelessWidget {
  final JournalEntry entry;
  final String? audioPath;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const JournalEntryCard({
    super.key,
    required this.entry,
    this.audioPath,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? BrandColors.charcoal : BrandColors.stone,
          width: 0.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: title + type icon + menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type indicator
                  _buildTypeIcon(isDark),
                  const SizedBox(width: 12),

                  // Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title.isNotEmpty ? entry.title : 'Untitled',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isDark ? BrandColors.softWhite : BrandColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (entry.durationSeconds != null && entry.durationSeconds! > 0)
                          Text(
                            _formatDuration(entry.durationSeconds!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: BrandColors.driftwood,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Menu button
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: BrandColors.driftwood,
                      size: 20,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit?.call();
                          break;
                        case 'delete':
                          onDelete?.call();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: BrandColors.error),
                            const SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: BrandColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Content preview
              if (entry.content.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _truncateContent(entry.content),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? BrandColors.stone : BrandColors.charcoal,
                    height: 1.5,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Linked file indicator
              if (entry.isLinked && entry.linkedFilePath != null) ...[
                const SizedBox(height: 12),
                _buildLinkedFileChip(context, isDark),
              ],

              // Audio indicator
              if (entry.hasAudio && audioPath != null) ...[
                const SizedBox(height: 12),
                _buildAudioChip(context, isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(bool isDark) {
    IconData icon;
    Color color;

    switch (entry.type) {
      case JournalEntryType.voice:
        icon = Icons.mic;
        color = BrandColors.turquoise;
      case JournalEntryType.linked:
        icon = Icons.link;
        color = BrandColors.forest;
      case JournalEntryType.text:
        icon = Icons.edit_note;
        color = BrandColors.driftwood;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 18,
        color: color,
      ),
    );
  }

  Widget _buildLinkedFileChip(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.forestMist.withValues(alpha: isDark ? 0.2 : 1.0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 14,
            color: BrandColors.forest,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              entry.linkedFilePath!.split('/').last,
              style: TextStyle(
                fontSize: 12,
                color: BrandColors.forest,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioChip(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.turquoiseMist.withValues(alpha: isDark ? 0.2 : 1.0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 14,
            color: BrandColors.turquoise,
          ),
          const SizedBox(width: 6),
          Text(
            'Play audio',
            style: TextStyle(
              fontSize: 12,
              color: BrandColors.turquoise,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _truncateContent(String content) {
    // Remove excessive whitespace
    final cleaned = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '$minutes min ${secs > 0 ? '$secs sec' : ''}';
    }
    return '$secs sec';
  }
}
