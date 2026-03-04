# Guide d'Intégration - Système d'Authentification BimStreaming

## 🔧 Comment Intégrer le Système d'Authentification dans la Gestion des Appareils

### 1. Vérifier les Permissions Avant d'Afficher les Contrôles

Dans `_buildDevicesPage()` ou similaire, avant d'afficher les boutons de modification:

```dart
// Récupérer l'utilisateur actuel
final currentUser = _currentAuthenticatedUser;

// Vérifier les permissions
bool canModifyThis = currentUser?.canModifyDevice(
  deviceCountry,  // Code pays de l'appareil
  deviceDepartment  // Code département de l'appareil
) ?? false;

// Afficher le bouton uniquement si autorisé
if (canModifyThis) {
  ElevatedButton(
    onPressed: () => _editDevice(device),
    child: const Text('Modifier'),
  ),
}
```

### 2. Exemple Complet - Liste des Appareils Filtrée

```dart
Widget _buildDevicesPage() {
  final currentUser = _currentAuthenticatedUser;
  
  if (currentUser == null) {
    return Center(child: Text('Non authentifié'));
  }

  // Filtrer les appareils selon le rôle
  final filteredDevices = _devices.where((device) {
    return currentUser.canViewDepartmentDevices() ||
           (currentUser.canViewCountryDevices() && device.country == currentUser.countryCode) ||
           (currentUser.canViewAllDevices());
  }).toList();

  return ListView.builder(
    itemCount: filteredDevices.length,
    itemBuilder: (context, index) {
      final device = filteredDevices[index];
      
      return _buildDeviceCard(
        device,
        canModify: currentUser.canModifyDevice(device.country, device.department),
        canDelete: currentUser.canDeleteDevice(device.country, device.department),
      );
    },
  );
}
```

### 3. Ajouter des Appareils avec Vérification

```dart
Future<void> _addDevice(String name, String country, String department) async {
  final currentUser = _currentAuthenticatedUser;
  
  if (currentUser == null) {
    _showError('Non authentifié');
    return;
  }

  // Vérifier les permissions
  if (!currentUser.canAddDevice(country, department)) {
    _showError(
      'Vous n\'avez pas la permission d\'ajouter des appareils à ${country}/${department}'
    );
    return;
  }

  // Procéder à l'ajout
  final newDevice = Device(
    id: _generateId(),
    name: name,
    country: country,
    department: department,
    createdBy: currentUser.id,
    createdAt: DateTime.now(),
  );

  setState(() {
    _devices.add(newDevice);
  });

  _showSuccess('Appareil ajouté avec succès');
}
```

### 4. Supprimer des Appareils avec Vérification

```dart
Future<void> _deleteDevice(Device device) async {
  final currentUser = _currentAuthenticatedUser;
  
  if (currentUser == null) {
    _showError('Non authentifié');
    return;
  }

  // Vérifier les permissions
  if (!currentUser.canDeleteDevice(device.country, device.department)) {
    _showError(
      'Vous n\'avez pas la permission de supprimer cet appareil'
    );
    return;
  }

  // Afficher une confirmation
  final confirmed = await _showConfirmDialog(
    'Confirmer la suppression',
    'Êtes-vous sûr de vouloir supprimer ${device.name}?',
  );

  if (confirmed) {
    setState(() {
      _devices.remove(device);
    });
    _showSuccess('Appareil supprimé');
  }
}
```

### 5. Afficher le Rôle et les Permissions dans l'Interface

```dart
String _getRoleBadgeLabel(UserRole role) {
  switch (role) {
    case UserRole.adminGlobal:
      return '👑 AG';
    case UserRole.adminPays:
      return '🌍 AP';
    case UserRole.adminDepartement:
      return '🏢 AD';
    case UserRole.client:
      return '👤 C';
  }
}

Color _getRoleBadgeColor(UserRole role) {
  switch (role) {
    case UserRole.adminGlobal:
      return Colors.red;
    case UserRole.adminPays:
      return Colors.orange;
    case UserRole.adminDepartement:
      return Colors.blue;
    case UserRole.client:
      return Colors.grey;
  }
}

// Dans l'AppBar
Widget _buildRoleBadge() {
  final role = _currentAuthenticatedUser?.role;
  if (role == null) return SizedBox.shrink();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: _getRoleBadgeColor(role),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      _getRoleBadgeLabel(role),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );
}
```

### 6. Logs d'Audit (Recommandé pour la Production)

```dart
void _logAuditEvent(String action, String details) {
  final currentUser = _currentAuthenticatedUser;
  
  if (currentUser == null) return;

  final auditLog = {
    'timestamp': DateTime.now(),
    'userId': currentUser.id,
    'userName': currentUser.name,
    'userRole': currentUser.role.label,
    'action': action,
    'details': details,
  };

  // Envoyer au backend
  // API.post('/audit-logs', auditLog);
  
  print('[AUDIT] $auditLog');
}

// Utilisation
_logAuditEvent('device_added', 'Device: $deviceName in $country/$department');
_logAuditEvent('device_deleted', 'Device: ${device.name} deleted');
_logAuditEvent('access_denied', 'Attempted to modify unauthorized device');
```

### 7. Gestion des Erreurs d'Accès

```dart
void _handleAccessDenied(String resource, String action) {
  final currentUser = _currentAuthenticatedUser;
  
  if (currentUser == null) {
    _showError('Veuillez vous authentifier');
    return;
  }

  _logAuditEvent('access_denied', '$action on $resource');
  
  _showError(
    'Accès refusé\n\n'
    'Votre rôle: ${currentUser.role.label}\n'
    'Zone: ${currentUser.countryCode ?? 'Global'}\n'
    'Action demandée: $action',
  );
}
```

### 8. Montrer les Zones Accessibles

```dart
Widget _buildAccessibleZones() {
  final currentUser = _currentAuthenticatedUser;
  
  if (currentUser == null) return SizedBox.shrink();

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Zones Accessibles'),
          const SizedBox(height: 12),
          if (currentUser.role == UserRole.adminGlobal)
            _buildZoneTile('🌍 GLOBAL', 'Accès à tous les appareils'),
          if (currentUser.role == UserRole.adminPays && currentUser.countryCode != null)
            _buildZoneTile(currentUser.countryCode!, 'Pays: ${currentUser.countryCode}'),
          if (currentUser.role == UserRole.adminDepartement && 
              currentUser.countryCode != null && 
              currentUser.departmentCode != null)
            _buildZoneTile(
              '${currentUser.countryCode}/${currentUser.departmentCode}',
              'Département: ${currentUser.departmentCode} en ${currentUser.countryCode}'
            ),
          if (currentUser.role == UserRole.client)
            _buildZoneTile('AUCUNE', 'Accès en lecture seule'),
        ],
      ),
    ),
  );
}

Widget _buildZoneTile(String zone, String description) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(zone, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ],
    ),
  );
}
```

## ⚙️ Configuration pour la Production

### 1. Remplacer les Mots de Passe en Dur

```dart
// ❌ AVANT
const String _principalAdminPassword = 'principal123';

// ✅ APRÈS - Depuis une BD ou API
Future<bool> _verifyPassword(String userId, String password) async {
  final response = await http.post(
    Uri.parse('https://api.bimstreaming.com/auth/verify'),
    body: {'userId': userId, 'password': password},
  );
  return response.statusCode == 200;
}
```

### 2. Activer le Hachage des Mots de Passe

```dart
import 'package:crypto/crypto.dart';

String _hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

// Ou mieux avec bcrypt
import 'package:bcrypt/bcrypt.dart';

String _hashPassword(String password) {
  return BCrypt.hashpw(password, BCrypt.gensalt());
}

bool _verifyPassword(String password, String hash) {
  return BCrypt.checkpw(password, hash);
}
```

### 3. Utiliser des Tokens JWT

```dart
import 'package:jwt_decoder/jwt_decoder.dart';

String _generateJWT(User user) {
  final now = DateTime.now();
  final payload = {
    'iss': 'bimstreaming',
    'sub': user.id,
    'name': user.name,
    'role': user.role.toString(),
    'country': user.countryCode,
    'department': user.departmentCode,
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'exp': now.add(Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000,
  };
  
  // Implémenter avec une vraie librairie JWT
  return jwtEncode(payload, secretKey);
}

bool _verifyJWT(String token) {
  try {
    final decodedToken = JwtDecoder.decode(token);
    final expirationDate = DateTime.fromMillisecondsSinceEpoch(
      decodedToken['exp'] * 1000,
    );
    return DateTime.now().isBefore(expirationDate);
  } catch (e) {
    return false;
  }
}
```

## 📚 Ressources Supplémentaires

- [Flutter Security Best Practices](https://flutter.dev/security)
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [JWT.io Debugger](https://jwt.io)

## 🐛 Dépannage

### L'utilisateur ne peut pas ajouter d'appareils
1. Vérifier le rôle de l'utilisateur
2. S'assurer que le code pays/département correspon

d
3. Vérifier les logs d'audit

### Les appareils n'apparaissent pas
1. Vérifier que l'utilisateur a les permissions de visualisation
2. Vérifier les filtres appliqués
3. Vérifier la configuration pays/département de l'appareil

### Permission refusée même pour admin
1. Vérifier que le code pays/département est exactement correct
2. Vérifier que le rôle est correctement assigné à l'utilisateur
3. Vérifier qu'il n'y a pas d'autre middleware qui bloque

---

**Dernière mise à jour**: 4 mars 2026
