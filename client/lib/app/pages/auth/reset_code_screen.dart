import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data_providers.dart';
import '../../widgets/app_toast.dart';

class ResetCodeScreen extends ConsumerStatefulWidget {
  const ResetCodeScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<ResetCodeScreen> createState() => _ResetCodeScreenState();
}

class _ResetCodeScreenState extends ConsumerState<ResetCodeScreen> {
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  bool _verifying = false;

  @override
  void dispose() {
    for (var node in _focusNodes) {
      node.dispose();
    }
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _verifyCode() async {
    if (_code.length != 6) {
      AppToast.show(context, 'Please enter all 6 digits', error: true);
      return;
    }

    setState(() => _verifying = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/auth/verify-reset-code',
            body: {'email': widget.email, 'code': _code},
          );
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Code verified. Enter your new password.');
      context.go('/auth/new-password?code=$_code', extra: widget.email);
    } catch (e) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, 'Invalid or expired code: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter verification code')),
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
                  const Text(
                    'We sent a 6-digit code to your email. Enter it below.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (i) {
                      return Container(
                        width: 50,
                        height: 50,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(1),
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) {
                            if (value.length == 1) {
                              if (i < 5) {
                                _focusNodes[i + 1].requestFocus();
                              } else {
                                _focusNodes[i].unfocus();
                              }
                            } else if (value.isEmpty && i > 0) {
                              _focusNodes[i - 1].requestFocus();
                            }
                            setState(() {});
                          },
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _verifying || _code.length != 6
                        ? null
                        : _verifyCode,
                    child: Text(_verifying ? 'Verifying...' : 'Verify code'),
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
