import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/space_notes/screens/link_capture_to_space_screen.dart';

/// Google Keep-inspired card for displaying recordings
/// Features: Compact design, voice indicator, transcript preview
class RecordingCard extends ConsumerWidget {
  final Recording recording;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;

  const RecordingCard({
    super.key,
    required this.recording,
    this.onTap,
    this.onDeleted,
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Recording'),
          content: const Text(
            'Are you sure you want to delete this recording? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true && context.mounted) {
      final success = await ref
          .read(storageServiceProvider)
          .deleteRecording(recording.id);
      if (success && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Recording deleted')));
        onDeleted?.call();
      }
    }
  }

  void _linkToSpaces(BuildContext context) async {
    String cleanNotePath = recording.filePath;
    if (cleanNotePath.startsWith('/api/')) {
      cleanNotePath = cleanNotePath.substring(5);
    }
    if (cleanNotePath.endsWith('.wav')) {
      cleanNotePath = cleanNotePath.replaceAll('.wav', '.md');
    }
    if (!cleanNotePath.startsWith('captures/')) {
      cleanNotePath = 'captures/$cleanNotePath';
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => LinkCaptureToSpaceScreen(
          captureId: recording.id,
          filename: recording.title,
          notePath: cleanNotePath,
        ),
      ),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully linked to spaces')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTranscript = recording.transcript.isNotEmpty;
    final hasContext = recording.context.isNotEmpty;
    final isProcessing =
        recording.transcriptionStatus == ProcessingStatus.processing ||
        recording.titleGenerationStatus == ProcessingStatus.processing;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isProcessing
            ? BorderSide(color: Colors.orange.shade300, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header: Voice badge + menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Voice note indicator badge
                  _buildVoiceNoteBadge(context),
                  const Spacer(),
                  // Menu button (compact)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'link',
                          child: Row(
                            children: [
                              Icon(Icons.link, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Link to Space',
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'delete') {
                          _confirmDelete(context, ref);
                        } else if (value == 'link') {
                          _linkToSpaces(context);
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Title
              Text(
                recording.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // Transcript preview (if available and not processing)
              if (hasTranscript && !isProcessing) ...[
                const SizedBox(height: 8),
                Text(
                  recording.transcript,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Processing indicator
              if (isProcessing) ...[
                const SizedBox(height: 8),
                _buildProcessingIndicator(context),
              ],

              // Context tag (if available)
              if (hasContext && !isProcessing) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade200, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.label, size: 12, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          recording.context,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Footer: metadata
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceNoteBadge(BuildContext context) {
    // Voice notes get a distinctive badge
    // In the future, text notes would have a different icon
    final isOmi = recording.source == RecordingSource.omiDevice;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOmi ? Colors.purple.shade50 : Colors.teal.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOmi ? Colors.purple.shade200 : Colors.teal.shade200,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOmi ? Icons.bluetooth : Icons.mic,
            size: 12,
            color: isOmi ? Colors.purple.shade700 : Colors.teal.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            isOmi ? 'Omi' : 'Voice',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOmi ? Colors.purple.shade700 : Colors.teal.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator(BuildContext context) {
    String statusText = 'Processing...';
    if (recording.transcriptionStatus == ProcessingStatus.processing) {
      statusText = 'Transcribing...';
    } else if (recording.titleGenerationStatus == ProcessingStatus.processing) {
      statusText = 'Generating title...';
    }

    return Row(
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.orange.shade600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          statusText,
          style: TextStyle(
            fontSize: 12,
            color: Colors.orange.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(
          recording.timeAgo,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 12),
        Icon(Icons.timer, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(
          recording.durationString,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
