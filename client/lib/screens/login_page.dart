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
        Text(
          role,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          'ID: $userId',
          style: TextStyle(color: Colors.grey[600]),
        ),
        Text(
          'MDP: $password',
          style: TextStyle(color: Colors.grey[600]),
        ),
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
    const double formMaxWidth = 430;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.1),
              // Logo
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? Colors.grey[800] : Colors.white,
                ),
                child: Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.blue[600],
                ),
              ),
              const SizedBox(height: 24),
              // Title
              Text(
                'BimStreaming',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.translate('secure_access'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.05),
              // User ID Input
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: formMaxWidth),
                  child: TextField(
                    controller: _userIdController,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      labelText: widget.translate('id_field_hint'),
                      hintText: widget.translate('id_field_hint'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey[800] : Colors.white,
                      prefixIcon: const Icon(Icons.person),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Password Input
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: formMaxWidth),
                  child: TextField(
                    controller: _passwordController,
                    enabled: !_isLoading,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: widget.translate('password_field_hint'),
                      hintText: widget.translate('password_field_hint'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey[800] : Colors.white,
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _showPassword = !_showPassword;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (_) => _handleLogin(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Error Message
              if (_errorMessage != null)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: formMaxWidth),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        border: Border.all(color: Colors.red[400]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red[900],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              // Login Button
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: formMaxWidth),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: Colors.blue[600],
                        disabledBackgroundColor: Colors.grey[400],
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(
                              widget.translate('authenticate_btn'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Demo Users Info Button
              TextButton.icon(
                onPressed: _showDemoUsers,
                icon: const Icon(Icons.info_outline),
                label: const Text('Voir les utilisateurs de démo'),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.1),
              // Footer
              Text(
                '© 2026 BimStreaming. Tous droits réservés.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
