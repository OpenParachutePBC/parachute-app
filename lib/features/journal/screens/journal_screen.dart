import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../models/journal_day.dart';
import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../widgets/journal_entry_card.dart';
import '../widgets/journal_input_bar.dart';

/// Main journal screen showing today's journal entries
///
/// The daily journal is the home for captures - voice notes, typed thoughts,
/// and links to longer recordings.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshJournal() async {
    ref.invalidate(selectedJournalProvider);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the selected date and its journal
    final selectedDate = ref.watch(selectedJournalDateProvider);
    final journalAsync = ref.watch(selectedJournalProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Check if viewing today
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, selectedDate, isToday, journalAsync),

            // Journal entries
            Expanded(
              child: journalAsync.when(
                data: (journal) => _buildJournalContent(context, journal),
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => _buildErrorState(context, error),
              ),
            ),

            // Input bar at bottom (only show for today)
            if (isToday)
              JournalInputBar(
                onTextSubmitted: (text) async {
                  final service = await ref.read(journalServiceFutureProvider.future);
                  await service.addTextEntry(content: text);
                  ref.invalidate(selectedJournalProvider);
                  _scrollToBottom();
                },
                onVoiceRecorded: (transcript, audioPath, duration) async {
                  final service = await ref.read(journalServiceFutureProvider.future);
                  await service.addVoiceEntry(
                    transcript: transcript,
                    audioPath: audioPath,
                    durationSeconds: duration,
                  );
                  ref.invalidate(selectedJournalProvider);
                  _scrollToBottom();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    DateTime selectedDate,
    bool isToday,
    AsyncValue<JournalDay> journalAsync,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Format the display date
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final displayDate = '${months[selectedDate.month - 1]} ${selectedDate.day}, ${selectedDate.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        border: Border(
          bottom: BorderSide(
            color: isDark ? BrandColors.charcoal : BrandColors.stone,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Date navigation (left arrow)
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: isDark ? BrandColors.driftwood : BrandColors.charcoal,
            ),
            onPressed: () {
              ref.read(selectedJournalDateProvider.notifier).state =
                  selectedDate.subtract(const Duration(days: 1));
            },
          ),

          Expanded(
            child: GestureDetector(
              onTap: () => _showDatePicker(context),
              child: Column(
                children: [
                  if (isToday)
                    Text(
                      'Today',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: BrandColors.forest,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    displayDate,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isDark ? BrandColors.softWhite : BrandColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // Date navigation (right arrow) - disabled if today
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: isToday
                  ? (isDark ? BrandColors.charcoal : BrandColors.stone)
                  : (isDark ? BrandColors.driftwood : BrandColors.charcoal),
            ),
            onPressed: isToday
                ? null
                : () {
                    ref.read(selectedJournalDateProvider.notifier).state =
                        selectedDate.add(const Duration(days: 1));
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final selectedDate = ref.read(selectedJournalDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(selectedJournalDateProvider.notifier).state = picked;
    }
  }

  Widget _buildJournalContent(BuildContext context, JournalDay journal) {
    // Check if viewing today
    final selectedDate = ref.read(selectedJournalDateProvider);
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    if (journal.isEmpty) {
      return _buildEmptyState(context, isToday);
    }

    return RefreshIndicator(
      onRefresh: _refreshJournal,
      color: BrandColors.forest,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: journal.entries.length,
        itemBuilder: (context, index) {
          final entry = journal.entries[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: JournalEntryCard(
              entry: entry,
              audioPath: journal.getAudioPath(entry.id),
              onTap: () => _showEntryDetail(context, entry),
              onEdit: () => _editEntry(context, entry),
              onDelete: () => _deleteEntry(context, journal, entry),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isToday) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isToday ? Icons.wb_sunny_outlined : Icons.history,
              size: 64,
              color: isDark ? BrandColors.driftwood : BrandColors.stone,
            ),
            const SizedBox(height: 16),
            Text(
              isToday ? 'Start your day' : 'No entries',
              style: theme.textTheme.titleLarge?.copyWith(
                color: isDark ? BrandColors.softWhite : BrandColors.charcoal,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isToday
                  ? 'Capture a thought, record a voice note,\nor just write something down.'
                  : 'No journal entries for this day.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isToday) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () {
                  // Go to today
                  ref.read(selectedJournalDateProvider.notifier).state = DateTime.now();
                },
                icon: const Icon(Icons.today),
                label: const Text('Go to Today'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: BrandColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                color: isDark ? BrandColors.softWhite : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshJournal,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEntryDetail(BuildContext context, JournalEntry entry) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? BrandColors.charcoal : BrandColors.stone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Type icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getEntryColor(entry.type).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getEntryIcon(entry.type),
                        color: _getEntryColor(entry.type),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title.isNotEmpty ? entry.title : 'Untitled',
                            style: theme.textTheme.titleLarge?.copyWith(
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
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: BrandColors.driftwood,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.content.isNotEmpty)
                        SelectableText(
                          entry.content,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: isDark ? BrandColors.stone : BrandColors.charcoal,
                            height: 1.6,
                          ),
                        )
                      else if (entry.isLinked && entry.linkedFilePath != null)
                        _buildLinkedFileInfo(context, entry.linkedFilePath!)
                      else
                        Text(
                          'No content',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: BrandColors.driftwood,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkedFileInfo(BuildContext context, String filePath) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BrandColors.forestMist.withValues(alpha: isDark ? 0.2 : 1.0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: BrandColors.forest,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Linked File',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: BrandColors.forest,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  filePath.split('/').last,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? BrandColors.softWhite : BrandColors.ink,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.open_in_new,
            color: BrandColors.forest,
            size: 20,
          ),
        ],
      ),
    );
  }

  IconData _getEntryIcon(JournalEntryType type) {
    switch (type) {
      case JournalEntryType.voice:
        return Icons.mic;
      case JournalEntryType.linked:
        return Icons.link;
      case JournalEntryType.text:
        return Icons.edit_note;
    }
  }

  Color _getEntryColor(JournalEntryType type) {
    switch (type) {
      case JournalEntryType.voice:
        return BrandColors.turquoise;
      case JournalEntryType.linked:
        return BrandColors.forest;
      case JournalEntryType.text:
        return BrandColors.driftwood;
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '$minutes min ${secs > 0 ? '$secs sec' : ''}';
    }
    return '$secs sec';
  }

  void _editEntry(BuildContext context, JournalEntry entry) {
    // TODO: Show edit dialog
    debugPrint('[JournalScreen] Edit entry: ${entry.id}');
  }

  Future<void> _deleteEntry(
    BuildContext context,
    JournalDay journal,
    JournalEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: BrandColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final service = await ref.read(journalServiceFutureProvider.future);
      await service.deleteEntry(journal.date, entry.id);
      ref.invalidate(selectedJournalProvider);
    }
  }
}
