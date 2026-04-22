import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/app_strings.dart';
import '../state/appearance_controller.dart';
import '../state/auth_controller.dart';
import '../state/data_providers.dart';
import '../widgets/confirm_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _darkMode = true;
  String _language = 'en';
  bool _desktopNotifications = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;

  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final mode = ref.read(themeModeProvider);
    _darkMode = mode == ThemeMode.dark;
    _language = ref.read(localeProvider).languageCode;
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveThemeAndLanguage() async {
    setState(() {
      _saving = true;
    });
    try {
      await ref
          .read(apiClientProvider)
          .patch(
            '/users/me',
            body: {
              'theme': _darkMode ? 'dark' : 'light',
              'language': _language,
            },
          );
      ref.read(themeModeProvider.notifier).state = _darkMode
          ? ThemeMode.dark
          : ThemeMode.light;
      await ref.read(localeProvider.notifier).setLocale(Locale(_language));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Theme and language saved')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _saveNotificationPrefs() async {
    try {
      await ref
          .read(apiClientProvider)
          .patch(
            '/users/me/notifications',
            body: {
              'desktop': _desktopNotifications,
              'email': _emailNotifications,
              'push': _pushNotifications,
            },
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences saved')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save preferences: $e')));
    }
  }

  Future<void> _changePassword() async {
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/auth/change-password',
            body: {
              'current_password': _currentPasswordController.text,
              'new_password': _newPasswordController.text,
            },
          );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Password change failed: $e')));
    }
  }

  Future<void> _deleteAccount() async {
    try {
      await ref.read(apiClientProvider).post('/users/me/delete');
      if (!mounted) {
        return;
      }
      await ref.read(authControllerProvider.notifier).logout();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deletion requested')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final strings = AppStrings.of(locale);
    if (_language != locale.languageCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _language != locale.languageCode) {
          setState(() {
            _language = locale.languageCode;
          });
        }
      });
    }
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: _darkMode,
            onChanged: (value) {
              setState(() => _darkMode = value);
              ref.read(themeModeProvider.notifier).state =
                  value ? ThemeMode.dark : ThemeMode.light;
            },
            title: Text(strings.theme),
            subtitle: Text(_darkMode ? strings.dark : strings.light),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: InputDecoration(
              labelText: strings.language,
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 'en', child: Text(strings.english)),
              DropdownMenuItem(value: 'fr', child: Text(strings.french)),
              DropdownMenuItem(value: 'es', child: Text(strings.spanish)),
              DropdownMenuItem(value: 'de', child: Text(strings.german)),
              DropdownMenuItem(value: 'it', child: Text(strings.italian)),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _language = value);
              unawaited(ref.read(localeProvider.notifier).setLocale(Locale(value)));
            },
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _saving ? null : _saveThemeAndLanguage,
            child: Text(_saving ? strings.saving : strings.saveAppearance),
          ),
          const Divider(height: 28),
          SwitchListTile(
            value: _desktopNotifications,
            onChanged: (value) => setState(() => _desktopNotifications = value),
            title: const Text('Desktop notifications'),
          ),
          SwitchListTile(
            value: _emailNotifications,
            onChanged: (value) => setState(() => _emailNotifications = value),
            title: const Text('Email notifications'),
          ),
          SwitchListTile(
            value: _pushNotifications,
            onChanged: (value) => setState(() => _pushNotifications = value),
            title: const Text('Push notifications'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saveNotificationPrefs,
            child: const Text('Save notifications'),
          ),
          const Divider(height: 28),
          TextField(
            controller: _currentPasswordController,
            decoration: const InputDecoration(
              labelText: 'Current password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newPasswordController,
            decoration: const InputDecoration(
              labelText: 'New password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _changePassword,
            child: const Text('Change password'),
          ),
          const Divider(height: 28),
          FilledButton(
            onPressed: () async {
              final confirm = await ConfirmDialog.show(
                context,
                title: 'Sign out',
                message: 'Do you want to end your current session?',
                confirmLabel: 'Sign out',
              );
              if (!confirm || !context.mounted) return;
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/auth/login');
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB23C3C),
            ),
            child: const Text('Sign out'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              final confirm = await ConfirmDialog.show(
                context,
                title: 'Delete account',
                message: 'This action is irreversible. Continue?',
                confirmLabel: 'Delete',
              );
              if (!confirm || !context.mounted) return;
              await _deleteAccount();
            },
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}
