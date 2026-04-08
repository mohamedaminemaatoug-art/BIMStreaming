// Énumération des rôles d'utilisateurs
enum UserRole {
  adminGlobal,      // Admin Principal - accès total
  adminPays,        // Admin Pays - accès aux devices du pays
  adminDepartement, // Admin Département - accès aux devices du département
  client            // Client - aucun accès
}

// Extension pour convertir le rôle en string lisible
extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.adminGlobal:
        return 'Admin Principal';
      case UserRole.adminPays:
        return 'Admin Pays';
      case UserRole.adminDepartement:
        return 'Admin Département';
      case UserRole.client:
        return 'Client';
    }
  }

  String get shortLabel {
    switch (this) {
      case UserRole.adminGlobal:
        return 'AG';
      case UserRole.adminPays:
        return 'AP';
      case UserRole.adminDepartement:
        return 'AD';
      case UserRole.client:
        return 'C';
    }
  }
}

// Modèle d'utilisateur
class User {
  final String id;
  final String name;
  final String password; // À hacher en production
  final UserRole role;
  final String? countryCode; // Pour Admin Pays
  final String? departmentCode; // Pour Admin Département
  final DateTime createdAt;
  final DateTime lastLogin;

  User({
    required this.id,
    required this.name,
    required this.password,
    required this.role,
    this.countryCode,
    this.departmentCode,
    DateTime? createdAt,
    DateTime? lastLogin,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastLogin = lastLogin ?? DateTime.now();

  // Vérifier les permissions
  bool canModifyDevice(String deviceCountry, String deviceDepartment) {
    switch (role) {
      case UserRole.adminGlobal:
        return true; // Accès total
      case UserRole.adminPays:
        return countryCode == deviceCountry; // Accès au pays
      case UserRole.adminDepartement:
        return departmentCode == deviceDepartment && 
               countryCode == deviceCountry; // Accès au département
      case UserRole.client:
        return false; // Aucun accès
    }
  }

  bool canAddDevice(String deviceCountry, String deviceDepartment) {
    return canModifyDevice(deviceCountry, deviceDepartment);
  }

  bool canDeleteDevice(String deviceCountry, String deviceDepartment) {
    return canModifyDevice(deviceCountry, deviceDepartment);
  }

  bool canViewAllDevices() {
    return role == UserRole.adminGlobal;
  }

  bool canViewCountryDevices() {
    return role == UserRole.adminGlobal || role == UserRole.adminPays;
  }

  bool canViewDepartmentDevices() {
    return role == UserRole.adminGlobal || 
           role == UserRole.adminPays || 
           role == UserRole.adminDepartement;
  }

  // Créer une copie avec modifications
  User copyWith({
    String? id,
    String? name,
    String? password,
    UserRole? role,
    String? countryCode,
    String? departmentCode,
    DateTime? createdAt,
    DateTime? lastLogin,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      password: password ?? this.password,
      role: role ?? this.role,
      countryCode: countryCode ?? this.countryCode,
      departmentCode: departmentCode ?? this.departmentCode,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }
}

// Classe para stocker les informations de session
class AuthSession {
  final User user;
  final String token;
  final DateTime loginTime;
  final DateTime expiryTime;

  AuthSession({
    required this.user,
    required this.token,
    required this.loginTime,
    Duration sessionDuration = const Duration(hours: 24),
  }) : expiryTime = loginTime.add(sessionDuration);

  bool get isExpired => DateTime.now().isAfter(expiryTime);

  bool get isValid => !isExpired;
}
