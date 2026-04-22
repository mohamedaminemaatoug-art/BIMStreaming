import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_controller.dart';
import '../../widgets/app_toast.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.error != null && next.error!.isNotEmpty) {
        AppToast.show(context, next.error!, error: true);
        ref.read(authControllerProvider.notifier).clearError();
      }
    });

    return Scaffold(
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
                  Text(
                    'Login',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _idController,
                    decoration: const InputDecoration(
                      labelText: 'Username or Email',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: auth.isLoading
                        ? null
                        : () {
                            ref
                                .read(authControllerProvider.notifier)
                                .login(
                                  _idController.text,
                                  _passwordController.text,
                                );
                          },
                    child: Text(auth.isLoading ? 'Signing in...' : 'Continue'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => context.go('/auth/forgot'),
                        child: const Text('Forgot password'),
                      ),
                      TextButton(
                        onPressed: () => context.go('/auth/register'),
                        child: const Text('Register'),
                      ),
                    ],
                  ),
                  if (auth.stage == AuthStage.twoFactorRequired)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('2FA required. Redirecting...'),
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
