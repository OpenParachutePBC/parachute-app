import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/services/parakeet_service.dart';

/// Platform-adaptive transcription setup step
///
/// Shows Parakeet v3 info - models download automatically on first use
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
  bool _isInitializingParakeet = false;
  bool _parakeetInitialized = false;
  String? _parakeetError;

  final bool _isApplePlatform = Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _checkParakeetStatus();
  }

  Future<void> _checkParakeetStatus() async {
    if (_isApplePlatform) {
      final parakeetService = ParakeetService();
      final isReady = await parakeetService.isReady();
      if (mounted) {
        setState(() {
          _parakeetInitialized = isReady;
        });
      }
    } else {
      // Android uses Sherpa-ONNX
      final transcriptionService = ref.read(
        transcriptionServiceAdapterProvider,
      );
      final isReady = await transcriptionService.isReady();
      if (mounted) {
        setState(() {
          _parakeetInitialized = isReady;
        });
      }
    }
  }

  Future<void> _initializeParakeet() async {
    setState(() {
      _isInitializingParakeet = true;
      _parakeetError = null;
    });

    try {
      if (_isApplePlatform) {
        final parakeetService = ParakeetService();
        await parakeetService.initialize(version: 'v3');
      } else {
        final transcriptionService = ref.read(
          transcriptionServiceAdapterProvider,
        );
        await transcriptionService.initialize();
      }

      if (mounted) {
        setState(() {
          _parakeetInitialized = true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Transcription Setup'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice Transcription',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Parachute uses Parakeet v3 for fast, offline transcription.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 32),

                      _buildParakeetInfo(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildBottomButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParakeetInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Parakeet v3',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFeatureItem(
              icon: Icons.speed,
              title: _isApplePlatform ? '~190x Real-time' : '~5x Real-time',
              subtitle: _isApplePlatform
                  ? 'Uses Apple Neural Engine'
                  : 'ONNX Runtime optimized',
            ),
            const SizedBox(height: 12),
            _buildFeatureItem(
              icon: Icons.language,
              title: '25 Languages',
              subtitle: 'Auto-detects language',
            ),
            const SizedBox(height: 12),
            _buildFeatureItem(
              icon: Icons.cloud_off,
              title: '100% Offline',
              subtitle: 'No internet required',
            ),
            const SizedBox(height: 12),
            _buildFeatureItem(
              icon: Icons.download,
              title: _isApplePlatform ? '~500 MB download' : '~640 MB download',
              subtitle: 'Downloads automatically on first use',
            ),
            if (_parakeetInitialized) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ready to use!',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_parakeetError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _parakeetError!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!_parakeetInitialized && _parakeetError == null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isInitializingParakeet
                      ? null
                      : _initializeParakeet,
                  icon: _isInitializingParakeet
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _isInitializingParakeet ? 'Downloading...' : 'Download Now',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: widget.onSkip,
            child: const Text('Skip'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: widget.onNext,
            child: const Text('Next'),
          ),
        ),
      ],
    );
  }
}
