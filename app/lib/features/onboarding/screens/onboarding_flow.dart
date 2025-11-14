import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'steps/welcome_step.dart';
import 'steps/transcription_setup_step.dart';
import 'steps/gemma_setup_step.dart';
import 'steps/advanced_features_step.dart';

/// Multi-step onboarding flow for first-time users
class OnboardingFlow extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingFlow({super.key, required this.onComplete});

  static const String _hasSeenOnboardingKey = 'has_seen_onboarding_v1';

  /// Check if user has completed onboarding
  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenOnboardingKey) ?? false;
  }

  /// Mark onboarding as completed
  static Future<void> markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenOnboardingKey, true);
  }

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  int _currentStep = 0;

  final List<OnboardingStepData> _steps = [
    OnboardingStepData(title: 'Welcome', icon: Icons.waving_hand),
    OnboardingStepData(title: 'Transcription', icon: Icons.transcribe),
    OnboardingStepData(title: 'Titles', icon: Icons.title),
    OnboardingStepData(title: 'Advanced', icon: Icons.tune),
  ];

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _completeOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _skipToEnd() {
    setState(() => _currentStep = _steps.length - 1);
  }

  Future<void> _completeOnboarding() async {
    await OnboardingFlow.markOnboardingComplete();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            _buildProgressIndicator(),

            // Current step content
            Expanded(
              child: IndexedStack(
                index: _currentStep,
                children: [
                  WelcomeStep(onNext: _nextStep, onSkip: _skipToEnd),
                  TranscriptionSetupStep(
                    onNext: _nextStep,
                    onBack: _previousStep,
                    onSkip: _skipToEnd,
                  ),
                  GemmaSetupStep(
                    onNext: _nextStep,
                    onBack: _previousStep,
                    onSkip: _skipToEnd,
                  ),
                  AdvancedFeaturesStep(
                    onComplete: _completeOnboarding,
                    onBack: _previousStep,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(_steps.length, (index) {
          final step = _steps[index];
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    // Step circle
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: isCompleted || isActive
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (index < _steps.length - 1)
                      Container(
                        width: 8,
                        height: 4,
                        color: isCompleted
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Step label
                Text(
                  step.title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class OnboardingStepData {
  final String title;
  final IconData icon;

  OnboardingStepData({required this.title, required this.icon});
}
