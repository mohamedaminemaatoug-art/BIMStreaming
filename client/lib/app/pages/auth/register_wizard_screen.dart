import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_controller.dart';
import '../../widgets/app_toast.dart';

class RegisterWizardScreen extends ConsumerStatefulWidget {
  const RegisterWizardScreen({super.key});

  @override
  ConsumerState<RegisterWizardScreen> createState() =>
      _RegisterWizardScreenState();
}

class _RegisterWizardScreenState extends ConsumerState<RegisterWizardScreen> {
  int _currentStep = 0;
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register account')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Card(
                  margin: const EdgeInsets.all(20),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Stepper(
                      currentStep: _currentStep,
                      onStepContinue: _onContinue,
                      onStepCancel: () {
                        if (_currentStep > 0) {
                          setState(() => _currentStep -= 1);
                        }
                      },
                      steps: [
                        Step(
                          title: const Text('Identity'),
                          content: Column(
                            children: [
                              TextField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _idController,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Step(
                          title: const Text('Security'),
                          content: TextField(
                            controller: _passwordController,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                            obscureText: true,
                          ),
                        ),
                        Step(
                          title: const Text('Contact'),
                          content: TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => context.go('/auth/login'),
                    child: const Text('Back to login'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onContinue() async {
    if (!mounted) {
      return;
    }

    if (_currentStep < 2) {
      setState(() => _currentStep += 1);
      return;
    }

    if (_nameController.text.trim().isEmpty ||
        _idController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty) {
      AppToast.show(
        context,
        'Please complete all registration fields',
        error: true,
      );
      return;
    }

    final authController = ref.read(authControllerProvider.notifier);
    await authController.register(
      username: _idController.text.trim(),
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }
    final auth = ref.read(authControllerProvider);

    if (auth.error != null && auth.error!.isNotEmpty) {
      AppToast.show(context, auth.error!, error: true);
      authController.clearError();
      return;
    }

    if (auth.stage == AuthStage.signedIn) {
      AppToast.show(context, 'Account created successfully.');
      context.go('/app/home');
      return;
    }

    if (auth.stage == AuthStage.twoFactorRequired) {
      AppToast.show(
        context,
        'Registration accepted. Enter your verification code.',
      );
      return;
    }

    AppToast.show(
      context,
      'Registration finished but verification is still required.',
      error: true,
    );
  }
}
