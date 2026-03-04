import 'package:bim_streaming/models/user_model.dart';

// Service d'authentification
class AuthService {
  static final AuthService _instance = AuthService._internal();
  
  AuthSession? _currentSession;
  
  // Base de données d'utilisateurs (à remplacer par une vraie BD)
  late final Map<String, User> _users;

  factory AuthService() {
    return _instance;
  }

  AuthService._internal() {
    _initializeUsers();
  }

  // Initialiser les utilisateurs de test
  void _initializeUsers() {
    _users = {
      'admin1': User(
        id: 'admin1',
        name: 'Admin Principal',
        password: 'admin123',
        role: UserRole.adminGlobal,
      ),
      'admin_fr': User(
        id: 'admin_fr',
        name: 'Admin France',
        password: 'france123',
        role: UserRole.adminPays,
        countryCode: 'FR',
      ),
      'admin_de_fr': User(
        id: 'admin_de_fr',
        name: 'Admin IT France',
        password: 'it_france123',
        role: UserRole.adminDepartement,
        countryCode: 'FR',
        departmentCode: 'IT',
      ),
      'client1': User(
        id: 'client1',
        name: 'Client Standard',
        password: 'client123',
        role: UserRole.client,
      ),
      'admin_us': User(
        id: 'admin_us',
        name: 'Admin USA',
        password: 'usa123',
        role: UserRole.adminPays,
        countryCode: 'US',
      ),
      'admin_de_us': User(
        id: 'admin_de_us',
        name: 'Admin HR USA',
        password: 'hr_usa123',
        role: UserRole.adminDepartement,
        countryCode: 'US',
        departmentCode: 'HR',
      ),
    };
  }

  // Authentifier un utilisateur
  Future<AuthResult> login(String userId, String password) async {
    try {
      // Simuler un délai réseau
      await Future.delayed(const Duration(milliseconds: 500));

      final user = _users[userId];
      
      if (user == null) {
        return AuthResult(
          success: false,
          message: 'Utilisateur non trouvé',
          errorCode: 'USER_NOT_FOUND',
        );
      }

      if (user.password != password) {
        return AuthResult(
          success: false,
          message: 'Mot de passe incorrect',
          errorCode: 'INVALID_PASSWORD',
        );
      }

      // Créer une session
      final token = _generateToken(user.id);
      _currentSession = AuthSession(
        user: user.copyWith(lastLogin: DateTime.now()),
        token: token,
        loginTime: DateTime.now(),
      );

      return AuthResult(
        success: true,
        message: 'Connexion réussie',
        user: _currentSession!.user,
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Erreur lors de la connexion: $e',
        errorCode: 'LOGIN_ERROR',
      );
    }
  }

  // Logout
  void logout() {
    _currentSession = null;
  }

  // Obtenir la session actuelle
  AuthSession? getCurrentSession() => _currentSession;

  // Vérifier si l'utilisateur est authentifié
  bool get isAuthenticated => _currentSession != null && _currentSession!.isValid;

  // Obtenir l'utilisateur actuel
  User? get currentUser => _currentSession?.user;

  // Générer un token (simplifié pour la démo)
  String _generateToken(String userId) {
    return 'token_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // Vérifier les permissions de l'utilisateur
  bool canModifyDevice(String deviceCountry, String deviceDepartment) {
    return currentUser?.canModifyDevice(deviceCountry, deviceDepartment) ?? false;
  }

  bool canAddDevice(String deviceCountry, String deviceDepartment) {
    return currentUser?.canAddDevice(deviceCountry, deviceDepartment) ?? false;
  }

  bool canDeleteDevice(String deviceCountry, String deviceDepartment) {
    return currentUser?.canDeleteDevice(deviceCountry, deviceDepartment) ?? false;
  }

  // Obtenir tous les utilisateurs (pour admins)
  List<User> getAllUsers() {
    if (currentUser?.role == UserRole.adminGlobal) {
      return _users.values.toList();
    }
    return [];
  }

  // Ajouter un nouvel utilisateur (Admin Global uniquement)
  Future<AuthResult> addUser(User newUser) async {
    if (currentUser?.role != UserRole.adminGlobal) {
      return AuthResult(
        success: false,
        message: 'Seul un Admin Principal peut ajouter des utilisateurs',
        errorCode: 'PERMISSION_DENIED',
      );
    }

    if (_users.containsKey(newUser.id)) {
      return AuthResult(
        success: false,
        message: 'Cet ID utilisateur existe déjà',
        errorCode: 'USER_ALREADY_EXISTS',
      );
    }

    _users[newUser.id] = newUser;
    return AuthResult(
      success: true,
      message: 'Utilisateur ajouté avec succès',
      user: newUser,
    );
  }

  // Supprimer un utilisateur (Admin Global uniquement)
  Future<AuthResult> deleteUser(String userId) async {
    if (currentUser?.role != UserRole.adminGlobal) {
      return AuthResult(
        success: false,
        message: 'Seul un Admin Principal peut supprimer des utilisateurs',
        errorCode: 'PERMISSION_DENIED',
      );
    }

    if (!_users.containsKey(userId)) {
      return AuthResult(
        success: false,
        message: 'Utilisateur non trouvé',
        errorCode: 'USER_NOT_FOUND',
      );
    }

    _users.remove(userId);
    return AuthResult(
      success: true,
      message: 'Utilisateur supprimé avec succès',
    );
  }

  // Mettre à jour le mot de passe (l'utilisateur courant)
  Future<AuthResult> updatePassword(String oldPassword, String newPassword) async {
    if (currentUser == null) {
      return AuthResult(
        success: false,
        message: 'Aucun utilisateur connecté',
        errorCode: 'NO_USER',
      );
    }

    if (currentUser!.password != oldPassword) {
      return AuthResult(
        success: false,
        message: 'Ancien mot de passe incorrect',
        errorCode: 'INVALID_OLD_PASSWORD',
      );
    }

    final updatedUser = currentUser!.copyWith(password: newPassword);
    _users[currentUser!.id] = updatedUser;
    _currentSession = _currentSession!.copyWith(user: updatedUser);

    return AuthResult(
      success: true,
      message: 'Mot de passe mis à jour avec succès',
      user: updatedUser,
    );
  }
}

// Résultat d'authentification
class AuthResult {
  final bool success;
  final String message;
  final User? user;
  final String? errorCode;

  AuthResult({
    required this.success,
    required this.message,
    this.user,
    this.errorCode,
  });
}

// Extension pour AuthSession
extension AuthSessionExtension on AuthSession {
  AuthSession copyWith({
    User? user,
    String? token,
    DateTime? loginTime,
    DateTime? expiryTime,
  }) {
    return AuthSession(
      user: user ?? this.user,
      token: token ?? this.token,
      loginTime: loginTime ?? this.loginTime,
      sessionDuration: expiryTime?.difference(loginTime ?? this.loginTime) ?? 
                       this.expiryTime.difference(this.loginTime),
    );
  }
}
