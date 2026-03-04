# Système d'Authentification BimStreaming

## 📋 Vue d'ensemble

BimStreaming dispose d'un système d'authentification complet avec gestion des rôles et permissions basée sur la hiérarchie. Le système contrôle l'accès à la modification et suppression des appareils selon le rôle de l'utilisateur.

## 👥 Rôles et Permissions

### 1. **Admin Principal** 👑
- **ID de démo**: `admin1`
- **Mot de passe de démo**: `admin123`
- **Permissions**:
  - ✅ Voir tous les appareils du système
  - ✅ Ajouter des appareils n'importe où
  - ✅ Modifier tous les appareils
  - ✅ Supprimer tous les appareils
  - ✅ Gestion des utilisateurs
  - ✅ Gestion complète du système

### 2. **Admin Pays** 🌍
- **ID de démo**: `admin_fr` (France) ou `admin_us` (USA)
- **Mot de passe de démo**: `france123` ou `usa123`
- **Permissions**:
  - ✅ Voir les appareils de son pays
  - ✅ Ajouter des appareils dans son pays
  - ✅ Modifier les appareils de son pays
  - ✅ Supprimer les appareils de son pays
  - ❌ Accès aux appareils d'autres pays
  - ❌ Gestion des utilisateurs

**Exemple**: L'Admin France ne peut gérer que les appareils français (FR)

### 3. **Admin Département** 🏢
- **ID de démo**: `admin_de_fr` (Département IT de France) ou `admin_de_us` (Département HR d'USA)
- **Mot de passe de démo**: `it_france123` ou `hr_usa123`
- **Permissions**:
  - ✅ Voir les appareils de son département
  - ✅ Ajouter des appareils dans son département
  - ✅ Modifier les appareils de son département
  - ✅ Supprimer les appareils de son département
  - ❌ Accès aux appareils d'autres départements
  - ❌ Gestion des utilisateurs

**Exemple**: L'Admin IT France peut gérer que les appareils du département IT en France (FR/IT)

### 4. **Client** 👤
- **ID de démo**: `client1`
- **Mot de passe de démo**: `client123`
- **Permissions**:
  - ❌ Voir les appareils
  - ❌ Ajouter des appareils
  - ❌ Modifier les appareils
  - ❌ Supprimer les appareils
  - ❌ Aucun accès à la gestion

## 🔐 Architecture de Sécurité

### Modèles
- **User Model** (`lib/models/user_model.dart`): Définit la structure utilisateur avec gestion des rôles
- **UserRole Enum**: Énumération des 4 rôles disponibles

### Services
- **AuthService** (`lib/services/auth_service.dart`): Service centralisé d'authentification
  - Gestion des sessions
  - Vérification des permissions
  - Gestion des utilisateurs (Admin Global)

### Pages
- **LoginPage** (`lib/screens/login_page.dart`): Interface de connexion avec boutons de démo
- **UserProfilePage** (`lib/screens/user_profile_page.dart`): Affiche le profil et les permissions de l'utilisateur

## 🚀 Utilisation

### Se Connecter
1. L'application affiche d'abord la page de **LoginPage**
2. Entrez un ID d'utilisateur et un mot de passe (voir les exemples ci-dessus)
3. Cliquez sur "S'authentifier" ou "Authenticate"

### Voir ses Permissions
1. Après connexion, accédez à l'onglet **"Profil"** dans le menu latéral
2. Consultez votre rôle et vos permissions détaillées
3. Cliquez sur "Déconnecter" pour vous déconnecter

### Gérer les Appareils
La gestion des appareils (ajout/suppression) respecte vos permissions:
- Les actions de modification ne s'affichent que pour les appareils auxquels vous avez accès
- Tentez de modifier un appareil hors de votre zone → Accès refusé

## 🔑 Points de Contrôle d'Accès

### Dans le Code
```dart
// Vérifier les permissions
bool canModify = _authService.canModifyDevice(deviceCountry, deviceDepartment);
if (canModify) {
  // Afficher les boutons de modification
}
```

### Vérification par Rôle
La classe `User` provides des méthodes:
- `canViewAllDevices()` - Voir tous les appareils
- `canViewCountryDevices()` - Voir les appareils du pays
- `canViewDepartmentDevices()` - Voir les appareils du département
- `canModifyDevice(country, dept)` - Modifier un appareil spécifique
- `canAddDevice(country, dept)` - Ajouter un appareil
- `canDeleteDevice(country, dept)` - Supprimer un appareil

## 📝 Ajouter un Nouvel Utilisateur

### Côté Code (AdminService)
```dart
// L'Admin Principal ajoute un nouvel utilisateur
final newUser = User(
  id: 'new_user_id',
  name: 'Nom Complet',
  password: 'securepwd123',
  role: UserRole.adminPays,
  countryCode: 'FR',
);

final result = await _authService.addUser(newUser);
```

## 🌐 Codes Pays et Départements

### Pays Supportés
- `'FR'` - France
- `'US'` - États-Unis
- Extensible pour ajouter d'autres pays

### Départements (Exemples)
- `'IT'` - Technologies de l'Information
- `'HR'` - Ressources Humaines
- `'SALES'` - Ventes (À ajouter)
- `'OPERATIONS'` - Opérations (À ajouter)

## 🔒 Sécurité Future

Pour un environnement productif, considérez:
- ✅ Hachage des mots de passe (bcrypt/argon2)
- ✅ Tokens JWT pour les sessions
- ✅ Authentification OAuth2/LDAP
- ✅ Logs d'audit complets
- ✅ 2FA/MFA
- ✅ Rate limiting sur les tentatives de connexion
- ✅ Stockage sécurisé des sessions

## 📱 Flux de l'Authentification

```
┌─────────────────────────────────────────┐
│   Lancement de l'Application            │
└──────────────┬──────────────────────────┘
               │
               ▼
        ┌─────────────────┐
        │  LoginPage      │
        │  (Identifiants) │
        └────────┬────────┘
                 │
                 ▼
      ┌─────────────────────┐
      │  AuthService.login()│
      │  - Vérif ID/MDP     │
      │  - Créer session    │
      └────────┬────────────┘
               │
        ┌──────┴──────┐
        │             │
       ✅           ❌
      Succès       Erreur
        │             │
        ▼             ▼
   ┌────────┐   ┌────────────┐
   │Interface│   │Afficher    │
   │Principale   │message erreur
   └────────┘   └────────────┘
```

## 🧪 Tests Rapides

### Test Admin Global
1. Se connecter: `admin1` / `admin123`
2. Profil affiche "Admin Principal" en rouge
3. Peut modifier tous les appareils

### Test Admin Pays
1. Se connecter: `admin_fr` / `france123`
2. Profil affiche "Admin Pays" - France
3. Peut modifier uniquement appareils FR

### Test Admin Département
1. Se connecter: `admin_de_fr` / `it_france123`
2. Profil affiche "Admin Département" - IT/France
3. Peut modifier uniquement appareils FR/IT

### Test Client
1. Se connecter: `client1` / `client123`
2. Profil affiche "Client" en gris
3. Aucun bouton de modification visible

---

**Version**: 1.0.0  
**Dernière mise à jour**: 4 mars 2026
