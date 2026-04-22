import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data_providers.dart';
import '../../widgets/app_toast.dart';

class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key, required this.email, required this.code});

  final String email;
  final String code;

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty || confirm.isEmpty) {
      AppToast.show(context, 'Both password fields are required', error: true);
      return;
    }

    if (password != confirm) {
      AppToast.show(
        context,
        'Password confirmation does not match',
        error: true,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/auth/reset-password',
            body: {
              'email': widget.email,
              'code': widget.code,
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
      appBar: AppBar(title: const Text('Set new password')),
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
