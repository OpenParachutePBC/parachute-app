import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/models/whisper_models.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/widgets/whisper_model_download_card.dart';
import 'package:app/services/parakeet_service.dart';

/// Platform-adaptive transcription setup step
///
/// - iOS/macOS: Shows Parakeet v3 download
/// - Android: Shows Whisper model selection
class TranscriptionSetupStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const TranscriptionSetupStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  ConsumerState<TranscriptionSetupStep> createState() =>
      _TranscriptionSetupStepState();
}

class _TranscriptionSetupStepState
    extends ConsumerState<TranscriptionSetupStep> {
  TranscriptionMode _selectedMode = TranscriptionMode.local;
  WhisperModelType? _recommendedModel = WhisperModelType.base;
  bool _hasDownloadedModel = false;
  bool _isInitializingParakeet = false;
  bool _parakeetInitialized = false;
  String? _parakeetError;

  final bool _isApplePlatform = Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_isApplePlatform) {
      _checkParakeetStatus();
    } else {
      _checkExistingWhisperModels();
    }
  }

  /// Check if Parakeet is already initialized (iOS/macOS)
  Future<void> _checkParakeetStatus() async {
    final parakeet = ParakeetService();
    final isReady = await parakeet.isReady();

    if (mounted) {
      setState(() {
        _parakeetInitialized = isReady;
        _hasDownloadedModel = isReady;
      });
    }
  }

  /// Initialize Parakeet models (iOS/macOS)
  Future<void> _initializeParakeet() async {
    if (_isInitializingParakeet || _parakeetInitialized) return;

    setState(() {
      _isInitializingParakeet = true;
      _parakeetError = null;
    });

    try {
      final parakeet = ParakeetService();
      await parakeet.initialize(version: 'v3');

      if (mounted) {
        setState(() {
          _parakeetInitialized = true;
          _hasDownloadedModel = true;
          _isInitializingParakeet = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _parakeetError = e.toString();
          _isInitializingParakeet = false;
        });
      }
    }
  }

  /// Check existing Whisper models (Android)
  Future<void> _checkExistingWhisperModels() async {
    final modelManager = ref.read(whisperModelManagerProvider);
    final downloadedModels = await modelManager.getDownloadedModels();

    if (downloadedModels.isNotEmpty && mounted) {
      setState(() {
        _hasDownloadedModel = true;
        _recommendedModel = downloadedModels.first;
      });
    }

    // Listen for downloads that complete while on this screen
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
            _isApplePlatform
                ? 'Download Parakeet v3 for fast, offline transcription'
                : 'Choose how to transcribe your voice recordings',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: SingleChildScrollView(
              child: _isApplePlatform
                  ? _buildParakeetSetup(context)
                  : _buildWhisperSetup(context),
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

                if (!_isApplePlatform && _recommendedModel != null) {
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

          // Helpful message
          if (_selectedMode == TranscriptionMode.local && !_hasDownloadedModel)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _isApplePlatform
                    ? 'Tip: Download continues in the background, you can proceed now'
                    : 'Tip: You can continue setup while downloads finish in the background',
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

  /// Build Parakeet setup UI (iOS/macOS)
  Widget _buildParakeetSetup(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.rocket_launch, color: Colors.blue[700], size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parakeet v3 ASR',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[900],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fast, high-quality transcription optimized for Apple Neural Engine',
                      style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Features list
        _buildFeatureItem(
          context,
          icon: Icons.speed,
          title: '~190x Real-time',
          subtitle: 'Transcribe 1 minute of audio in <1 second',
        ),
        const SizedBox(height: 12),
        _buildFeatureItem(
          context,
          icon: Icons.language,
          title: '25 Languages',
          subtitle: 'Multilingual support with auto-detection',
        ),
        const SizedBox(height: 12),
        _buildFeatureItem(
          context,
          icon: Icons.cloud_off,
          title: '100% Offline',
          subtitle: 'Private, no internet required',
        ),
        const SizedBox(height: 12),
        _buildFeatureItem(
          context,
          icon: Icons.storage,
          title: '~500 MB',
          subtitle: 'One-time download from HuggingFace',
        ),

        const SizedBox(height: 24),

        // Download button or status
        if (_parakeetInitialized)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ready to go!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[900],
                        ),
                      ),
                      Text(
                        'Parakeet v3 is downloaded and ready',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else if (_isInitializingParakeet)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.orange[700],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Downloading models...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      Text(
                        'This may take a few minutes (~500 MB)',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _initializeParakeet,
              icon: const Icon(Icons.download),
              label: const Text('Download Parakeet v3'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

        // Error message
        if (_parakeetError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Download failed: $_parakeetError',
                      style: TextStyle(fontSize: 12, color: Colors.red[900]),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Build Whisper setup UI (Android)
  Widget _buildWhisperSetup(BuildContext context) {
    return Column(
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
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Download a model to transcribe offline. We recommend Base for the best balance.',
                    style: TextStyle(fontSize: 13, color: Colors.blue[900]),
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
                Icon(Icons.cloud_outlined, size: 64, color: Colors.grey[400]),
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
    );
  }

  Widget _buildFeatureItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
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
