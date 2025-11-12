import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/models/whisper_models.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/widgets/whisper_model_download_card.dart';

class WhisperSetupStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const WhisperSetupStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  ConsumerState<WhisperSetupStep> createState() => _WhisperSetupStepState();
}

class _WhisperSetupStepState extends ConsumerState<WhisperSetupStep> {
  TranscriptionMode _selectedMode = TranscriptionMode.local;
  WhisperModelType? _recommendedModel = WhisperModelType.base;
  bool _hasDownloadedModel = false;

  @override
  void initState() {
    super.initState();
    _checkExistingModels();
  }

  Future<void> _checkExistingModels() async {
    final modelManager = ref.read(whisperModelManagerProvider);
    final downloadedModels = await modelManager.getDownloadedModels();

    if (downloadedModels.isNotEmpty && mounted) {
      setState(() {
        _hasDownloadedModel = true;
        // Set the first downloaded model as recommended
        _recommendedModel = downloadedModels.first;
      });
    }

    // Also listen for downloads that complete while on this screen
    modelManager.progressStream.listen((progress) {
      if (progress.state == ModelDownloadState.downloaded && mounted) {
        setState(() {
          _hasDownloadedModel = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
              const Spacer(),
              TextButton(onPressed: widget.onSkip, child: const Text('Skip')),
            ],
          ),

          const SizedBox(height: 8),

          // Title
          Text(
            'Transcription Setup',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(
            'Choose how to transcribe your voice recordings',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 16),

          // Everything below header should be scrollable
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mode selection (compact)
                  Row(
                    children: [
                      Expanded(
                        child: _buildModeCard(
                          context,
                          mode: TranscriptionMode.local,
                          title: 'Local',
                          subtitle: 'Private & Offline',
                          icon: Icons.download,
                          recommended: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildModeCard(
                          context,
                          mode: TranscriptionMode.api,
                          title: 'Cloud',
                          subtitle: 'OpenAI API',
                          icon: Icons.cloud,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Model selection (if local mode)
                  if (_selectedMode == TranscriptionMode.local) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Download a model to transcribe offline. We recommend Base for the best balance.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Model cards
                    ...WhisperModelType.values.map(
                      (model) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: WhisperModelDownloadCard(
                          modelType: model,
                          isPreferred: model == _recommendedModel,
                          onSetPreferred: () {
                            setState(() => _recommendedModel = model);
                          },
                          onDownloadComplete: () {
                            setState(() => _hasDownloadedModel = true);
                          },
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 32),
                    Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'You\'ll need an OpenAI API key',
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'You can add it later in Settings',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Continue button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                // Save the selected mode
                await ref
                    .read(storageServiceProvider)
                    .setTranscriptionMode(_selectedMode.name);
                if (_recommendedModel != null) {
                  await ref
                      .read(storageServiceProvider)
                      .setPreferredWhisperModel(_recommendedModel!.modelName);
                }
                widget.onNext();
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Helpful message if download is in progress
          if (_selectedMode == TranscriptionMode.local && !_hasDownloadedModel)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Tip: You can continue setup while downloads finish in the background',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required TranscriptionMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    bool recommended = false,
  }) {
    final isSelected = _selectedMode == mode;

    return InkWell(
      onTap: () => setState(() => _selectedMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            if (recommended)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'RECOMMENDED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Icon(
              icon,
              size: 32,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[600],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Colors.grey[800],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                    : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
