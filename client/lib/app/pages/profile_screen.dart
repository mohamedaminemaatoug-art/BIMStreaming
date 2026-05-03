import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_strings.dart';
import '../state/appearance_controller.dart';
import '../state/data_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.userId});

  final String? userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _statusEmojiController = TextEditingController();
  final TextEditingController _statusMessageController = TextEditingController();

  Map<String, dynamic> _user = const {};
  String _availability = 'online';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _statusEmojiController.dispose();
    _statusMessageController.dispose();
    super.dispose();
  }

  String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is Map) {
      final valid = value['Valid'];
      if (valid == false) {
        return fallback;
      }
      final nested = value['String'];
      if (nested != null) {
        final nestedText = nested.toString().trim();
        if (nestedText.isNotEmpty && nestedText != 'null') {
          return nestedText;
        }
      }
      return fallback;
    }
    final text = value.toString().trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _displayNameFromUser() {
    final displayName = _stringValue(_user['display_name']);
    if (displayName.isNotEmpty) return displayName;

    final username = _stringValue(_user['username']);
    if (username.isNotEmpty) return username;

    final email = _stringValue(_user['email'], fallback: 'User');
    return email.split('@').first;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'away':
        return const Color(0xFFF4A62A);
      case 'busy':
        return const Color(0xFFC53A2E);
      case 'offline':
        return const Color(0xFF7A8B97);
      default:
        return const Color(0xFF0EA271);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final me = await api.get('/users/me');
      final user = Map<String, dynamic>.from((me['user'] as Map?) ?? me);

      if (!mounted) return;
      setState(() {
        _user = user;
      });

      _displayNameController.text = _displayNameFromUser();
      _bioController.text = _sanitizeBio(_stringValue(user['bio']));
      _availability = 'online';

      try {
        final statusResponse = await api.get('/users/me/status');
        final status = Map<String, dynamic>.from(
          (statusResponse['status'] as Map?) ?? const {},
        );

        if (mounted) {
          setState(() {
            _statusEmojiController.text = _stringValue(status['emoji']);
            _statusMessageController.text = _stringValue(status['message']);
            final statusValue = _stringValue(
              status['availability'],
              fallback: 'online',
            ).toLowerCase();
            _availability = switch (statusValue) {
              'away' => 'away',
              'busy' => 'busy',
              'offline' => 'offline',
              _ => 'online',
            };
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _availability = 'online';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    try {
      await ref.read(apiClientProvider).patch(
        '/users/me',
        body: {
          'display_name': _displayNameController.text.trim(),
          'bio': _bioController.text.trim(),
        },
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e')),
      );
    }
  }

  Future<void> _saveStatus() async {
    try {
      await ref.read(apiClientProvider).patch(
        '/users/me/status',
        body: {
          'emoji': _statusEmojiController.text.trim(),
          'message': _statusMessageController.text.trim(),
          'availability': _availability,
        },
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _uploadAvatar() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.image);
      if (picked == null || picked.files.isEmpty) return;

      final path = picked.files.single.path;
      if (path == null || path.isEmpty) return;

      await ref.read(apiClientProvider).postMultipart(
        '/users/me/avatar',
        fieldName: 'avatar',
        file: File(path),
      );

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar uploaded successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Avatar upload failed: $e')),
      );
    }
  }

  String _sanitizeBio(String text) {
    if (text.isEmpty) return '';
    final cleaned = text.replaceAll(RegExp(r'\{String:\s*,\s*Valid:\s*false\}'), '');
    return cleaned.trim();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref.watch(localeProvider));
    final viewingOwn = widget.userId == null;
    final avatarUrl = _stringValue(_user['avatar_url']);
    final email = _stringValue(_user['email']);
    final displayName = _displayNameController.text.trim().isEmpty
        ? _displayNameFromUser()
        : _displayNameController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(viewingOwn ? strings.myProfile : strings.userProfile),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(strings.unableToLoadProfileRightNow),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _load,
                        child: Text(strings.retry),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundImage: avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl.isEmpty
                                  ? Text(
                                      displayName.isNotEmpty
                                          ? displayName.characters.first.toUpperCase()
                                          : '?',
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  if (email.isNotEmpty) Text(email),
                                  const SizedBox(height: 4),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _statusColor(_availability),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _availability.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.profileInformation,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _displayNameController,
                              enabled: viewingOwn,
                              decoration: InputDecoration(
                                labelText: strings.displayName,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _bioController,
                              enabled: viewingOwn,
                              minLines: 3,
                              maxLines: 5,
                              decoration: InputDecoration(
                                labelText: strings.bio,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            if (viewingOwn) ...[
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _saveProfile,
                                child: Text(strings.saveProfile),
                              ),
                            ],
                            const SizedBox(height: 24),
                            Text(
                              strings.status,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _statusEmojiController,
                              enabled: viewingOwn,
                              decoration: InputDecoration(
                                labelText: strings.emoji,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _statusMessageController,
                              enabled: viewingOwn,
                              decoration: InputDecoration(
                                labelText: strings.statusMessage,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _availability,
                              decoration: InputDecoration(
                                labelText: strings.availability,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: [
                                DropdownMenuItem(value: 'online', child: Text(strings.online)),
                                DropdownMenuItem(value: 'away', child: Text(strings.away)),
                                DropdownMenuItem(value: 'busy', child: Text(strings.busy)),
                                DropdownMenuItem(value: 'offline', child: Text(strings.offline)),
                              ],
                              onChanged: viewingOwn
                                  ? (value) {
                                      if (value != null) {
                                        setState(() {
                                          _availability = value;
                                        });
                                      }
                                    }
                                  : null,
                            ),
                            if (viewingOwn) ...[
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _saveStatus,
                                child: Text(strings.saveStatus),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}