import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/space_provider.dart';

class CreateSpaceDialog extends ConsumerStatefulWidget {
  const CreateSpaceDialog({super.key});

  @override
  ConsumerState<CreateSpaceDialog> createState() => _CreateSpaceDialogState();
}

class _CreateSpaceDialogState extends ConsumerState<CreateSpaceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  // Icon and color selection
  String? _selectedIcon;
  Color? _selectedColor;

  // Common emoji icons for spaces
  final List<String> _availableIcons = [
    '📁',
    '💼',
    '🏠',
    '🎯',
    '💡',
    '🎨',
    '🔬',
    '📚',
    '🎵',
    '🎮',
    '💰',
    '🏋️',
    '🍳',
    '✈️',
    '🌱',
    '⚡',
  ];

  // Common colors for spaces
  final List<Color> _availableColors = [
    const Color(0xFF2E7D32), // Green
    const Color(0xFF1976D2), // Blue
    const Color(0xFFD32F2F), // Red
    const Color(0xFFF57C00), // Orange
    const Color(0xFF7B1FA2), // Purple
    const Color(0xFF0097A7), // Cyan
    const Color(0xFFC2185B), // Pink
    const Color(0xFF5D4037), // Brown
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Sphere'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'My Project',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
                enabled: !_isLoading,
              ),
              const SizedBox(height: 24),

              // Icon Picker
              Text(
                'Icon (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableIcons.map((icon) {
                  final isSelected = _selectedIcon == icon;
                  return InkWell(
                    onTap: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _selectedIcon = isSelected ? null : icon;
                            });
                          },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : null,
                      ),
                      child: Center(
                        child: Text(icon, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Color Picker
              Text(
                'Color (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableColors.map((color) {
                  final isSelected = _selectedColor == color;
                  return InkWell(
                    onTap: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _selectedColor = isSelected ? null : color;
                            });
                          },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.black, width: 3)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _createSpace,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createSpace() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Convert Color to hex string if selected
      String? colorHex;
      if (_selectedColor != null) {
        // Use toARGB32 for explicit color value conversion
        colorHex =
            '#${_selectedColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
      }

      await ref
          .read(spaceActionsProvider)
          .createSpace(
            name: _nameController.text.trim(),
            icon: _selectedIcon,
            color: colorHex,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Space created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating space: $e')));
      }
    }
  }
}
