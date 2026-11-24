import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

const avatarEmojis = [
  '😀',
  '😎',
  '🤠',
  '🦁',
  '🐯',
  '🦊',
  '🐼',
  '🐨',
  '🦅',
  '🐬',
  '🌴',
  '⚽',
  '🚀',
  '🌍',
  '🎒',
  '🧭',
];

Future<void> showProfileSheet(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileSheet(app: app),
  );
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.app});
  final AppState app;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final _name = TextEditingController(text: widget.app.profile!.name);
  late int _color = widget.app.profile!.colorIndex;
  String? _emoji;
  String? _photo;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _emoji = widget.app.profile!.emoji;
    _photo = widget.app.profile!.photoUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    final hadPhoto = (widget.app.profile!.photoUrl ?? '').isNotEmpty;
    if (hadPhoto && _photo == null) {
      await widget.app.repo.deleteAvatar();
    }
    await widget.app.saveProfile(
      Profile(name: n, colorIndex: _color, emoji: _emoji, photoUrl: _photo),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Gallery only (Android's system photo picker: no permission needed).
      // Shrunk on the phone to ~256 px / ~20 KB before upload.
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 70,
      );
      if (x == null) return;
      setState(() => _uploading = true);
      final url = await widget.app.repo.uploadAvatar(await x.readAsBytes());
      if (!mounted) return;
      setState(() {
        _uploading = false;
        if (url != null) _photo = url;
      });
      if (url == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Photos need Firebase (not in demo mode).'),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _uploading = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not upload the photo. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        decoration: BoxDecoration(
          color: context.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Avatar(
                  name: _name.text,
                  colorIndex: _color,
                  size: 84,
                  emoji: _emoji,
                  photoUrl: _photo,
                ),
              ),
              const SizedBox(height: 10),
              if (!widget.app.repo.isDemo)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _uploading ? null : _pickPhoto,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_rounded, size: 18),
                      label: Text(
                        (_photo ?? '').isEmpty
                            ? 'Choose photo'
                            : 'Change photo',
                      ),
                    ),
                    if ((_photo ?? '').isNotEmpty)
                      TextButton(
                        onPressed: _uploading
                            ? null
                            : () => setState(() => _photo = null),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Your name'),
              ),
              const SizedBox(height: 16),
              Text('Avatar', style: TextStyle(color: context.muted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    context,
                    selected: _emoji == null,
                    onTap: () => setState(() {
                      _emoji = null;
                      _photo = null;
                    }),
                    child: const Text(
                      'Aa',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  for (final e in avatarEmojis)
                    _chip(
                      context,
                      selected: _emoji == e,
                      onTap: () => setState(() {
                        _emoji = e;
                        _photo = null;
                      }),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Colour', style: TextStyle(color: context.muted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < Brand.memberColors.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _color = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Brand.memberColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.text,
                            width: i == _color ? 3 : 0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Appearance', style: TextStyle(color: context.muted)),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: widget.app,
                builder: (_, _) => SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('Auto'),
                      icon: Icon(Icons.brightness_auto_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_rounded),
                    ),
                  ],
                  selected: {widget.app.themeMode},
                  onSelectionChanged: (s) => widget.app.setThemeMode(s.first),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Brand.teal : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: child,
      ),
    );
  }
}
