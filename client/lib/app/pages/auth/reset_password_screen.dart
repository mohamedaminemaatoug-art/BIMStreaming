import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data_providers.dart';
import '../../widgets/app_toast.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.tokenFromLink});

  final String? tokenFromLink;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tokenController.text = widget.tokenFromLink ?? '';
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _tokenController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (token.isEmpty || password.isEmpty || confirm.isEmpty) {
      AppToast.show(context, 'All fields are required', error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/auth/reset-password',
            body: {
              'token': token,
              'password': password,
              'confirm_password': confirm,
            },
          );
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Password reset successful. Please login.');
      context.go('/auth/login');
    } catch (e) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Reset failed: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(labelText: 'Reset token'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(
                      _submitting ? 'Resetting...' : 'Reset password',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
