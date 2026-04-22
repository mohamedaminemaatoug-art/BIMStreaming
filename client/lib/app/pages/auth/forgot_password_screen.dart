import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data_providers.dart';
import '../../widgets/app_toast.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recover account')),
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
                  const Text('Enter your email to receive a reset code.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            final email = _emailController.text.trim();
                            if (email.isEmpty) {
                              AppToast.show(
                                context,
                                'Please enter your email address',
                                error: true,
                              );
                              return;
                            }
                            setState(() => _sending = true);
                            try {
                              await ref
                                  .read(apiClientProvider)
                                  .post(
                                    '/auth/forgot-password',
                                    body: {'email': email},
                                  );
                              if (!mounted) {
                                return;
                              }
                              AppToast.show(
                                context,
                                'Check your email for a reset code.',
                              );
                              context.go('/auth/reset-code', extra: email);
                            } catch (e) {
                              if (!mounted) {
                                return;
                              }
                              AppToast.show(
                                context,
                                'Failed to send reset code: $e',
                                error: true,
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _sending = false);
                              }
                            }
                          },
                    child: Text(_sending ? 'Sending...' : 'Send reset code'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/auth/login'),
                    child: const Text('Back to login'),
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
