import 'package:flutter/material.dart';
import 'package:bim_streaming/models/user_model.dart';
import 'package:bim_streaming/services/auth_service.dart';

class LoginPage extends StatefulWidget {
  final Function(User) onLoginSuccess;
  final bool isDarkMode;
  final String Function(String) translate;

  const LoginPage({
    super.key,
    required this.onLoginSuccess,
    required this.isDarkMode,
    required this.translate,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _showPassword = false;
  String? _errorMessage;

  @override
  void dispose() {
    _userIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final userId = _userIdController.text.trim();
    final password = _passwordController.text;

    if (userId.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = widget.translate('auth_fill_all_fields');
        _isLoading = false;
      });
      return;
    }

    final result = await _authService.login(userId, password);

    if (!mounted) return;

    if (result.success && result.user != null) {
      widget.onLoginSuccess(result.user!);
    } else {
      setState(() {
        _errorMessage = result.message;
        _isLoading = false;
      });
    }
  }

  void _showDemoUsers() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Utilisateurs de Démo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDemoUserTile(
                'Admin Principal',
                'admin1',
                'admin123',
                'Accès total à tous les devices',
              ),
              const Divider(),
              _buildDemoUserTile(
                'Admin France',
                'admin_fr',
                'france123',
                'Accès aux devices de France',
              ),
              const Divider(),
              _buildDemoUserTile(
                'Admin IT France',
                'admin_de_fr',
                'it_france123',
                'Accès aux devices IT de France',
              ),
              const Divider(),
              _buildDemoUserTile(
                'Client',
                'client1',
                'client123',
                'Aucun accès de modification',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoUserTile(
    String role,
    String userId,
    String password,
    String description,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(role, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text('ID: $userId', style: TextStyle(color: Colors.grey[600])),
        Text('MDP: $password', style: TextStyle(color: Colors.grey[600])),
        Text(
          description,
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    const double formMaxWidth = 460;
    final panelColor = isDark
        ? const Color(0xFF14202A)
        : const Color(0xFFF8FBFF);
    final fieldColor = isDark ? const Color(0xFF0E1822) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2B3B4A)
        : const Color(0xFFD3DFEA);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF07121A),
                          Color(0xFF0A2535),
                          Color(0xFF12384C),
                        ]
                      : const [
                          Color(0xFFF0FAFF),
                          Color(0xFFDFF3FF),
                          Color(0xFFFDF7EA),
                        ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -80,
            child: _orb(const Color(0xFF1CA7EC).withValues(alpha: 0.30), 240),
          ),
          Positioned(
            bottom: -140,
            right: -100,
            child: _orb(const Color(0xFFFFB457).withValues(alpha: 0.22), 300),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.96, end: 1.0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: formMaxWidth),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                    decoration: BoxDecoration(
                      color: panelColor.withValues(alpha: isDark ? 0.94 : 0.92),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: borderColor.withValues(alpha: 0.55),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.34 : 0.14,
                          ),
                          blurRadius: 42,
                          spreadRadius: 0,
                          offset: const Offset(0, 24),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF1CA7EC),
                                    Color(0xFF0A70B8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BimStreaming',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF13202A),
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  Text(
                                    widget.translate('secure_access'),
                                    style: TextStyle(
                                      color: isDark
                                          ? const Color(0xFFA8C2D4)
                                          : const Color(0xFF5A7688),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        TextField(
                          controller: _userIdController,
                          enabled: !_isLoading,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A2A35),
                          ),
                          decoration: _fieldDecoration(
                            isDark: isDark,
                            fillColor: fieldColor,
                            borderColor: borderColor,
                            label: widget.translate('id_field_hint'),
                            icon: Icons.badge_outlined,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          enabled: !_isLoading,
                          obscureText: !_showPassword,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A2A35),
                          ),
                          decoration: _fieldDecoration(
                            isDark: isDark,
                            fillColor: fieldColor,
                            borderColor: borderColor,
                            label: widget.translate('password_field_hint'),
                            icon: Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _handleLogin(),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE8E6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFF9D95),
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFF8F231C),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F8DCC),
                            disabledBackgroundColor: Colors.blueGrey,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.translate('authenticate_btn'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _showDemoUsers,
                          icon: const Icon(Icons.info_outline_rounded),
                          label: const Text('Voir les utilisateurs de demo'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '© 2026 BimStreaming. Tous droits reserves.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF8BA5B6)
                                : const Color(0xFF6D8798),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orb(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required bool isDark,
    required Color fillColor,
    required Color borderColor,
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: fillColor,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      labelStyle: TextStyle(
        color: isDark ? const Color(0xFFA9C3D5) : const Color(0xFF5B7385),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Color(0xFF0F8DCC), width: 1.3),
      ),
    );
  }
}
