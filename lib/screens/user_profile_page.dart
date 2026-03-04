import 'package:flutter/material.dart';
import 'package:bim_streaming/models/user_model.dart';

class UserProfilePage extends StatelessWidget {
  final User user;
  final VoidCallback onLogout;
  final bool isDarkMode;
  final String Function(String) translate;

  const UserProfilePage({
    super.key,
    required this.user,
    required this.onLogout,
    required this.isDarkMode,
    required this.translate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode;
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Card
            Card(
              color: isDark ? Colors.grey[800] : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.blue[600],
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ID: ${user.id}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Role Card
            Card(
              color: isDark ? Colors.grey[800] : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translate('current_role'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _getRoleColor(user.role),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.role.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Permissions
            Text(
              'Permissions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            _buildPermissionTile(
              icon: Icons.visibility,
              title: 'Voir les appareils',
              description: _getViewPermissionDescription(user),
              isDark: isDark,
            ),
            _buildPermissionTile(
              icon: Icons.edit,
              title: 'Modifier les appareils',
              description: _getModifyPermissionDescription(user),
              isDark: isDark,
              canAccess: user.role != UserRole.client,
            ),
            _buildPermissionTile(
              icon: Icons.add_circle,
              title: 'Ajouter des appareils',
              description: _getAddPermissionDescription(user),
              isDark: isDark,
              canAccess: user.role != UserRole.client,
            ),
            _buildPermissionTile(
              icon: Icons.delete,
              title: 'Supprimer des appareils',
              description: _getDeletePermissionDescription(user),
              isDark: isDark,
              canAccess: user.role != UserRole.client,
            ),
            const SizedBox(height: 24),
            // Region Info
            if (user.role == UserRole.adminPays || 
                user.role == UserRole.adminDepartement)
              ...[
                Card(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Informations de Zone',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (user.countryCode != null)
                          _buildInfoTile(
                            'Pays',
                            user.countryCode!,
                            isDark,
                          ),
                        if (user.departmentCode != null)
                          _buildInfoTile(
                            'Département',
                            user.departmentCode!,
                            isDark,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            // Logout Button
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirmation'),
                    content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onLogout();
                        },
                        child: const Text(
                          'Déconnecter',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Déconnecter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
    bool canAccess = true,
  }) {
    return Card(
      color: isDark ? Colors.grey[800] : Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              icon,
              color: canAccess ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              canAccess ? Icons.check_circle : Icons.cancel,
              color: canAccess ? Colors.green : Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.adminGlobal:
        return Colors.red[600]!;
      case UserRole.adminPays:
        return Colors.orange[600]!;
      case UserRole.adminDepartement:
        return Colors.blue[600]!;
      case UserRole.client:
        return Colors.grey[600]!;
    }
  }

  String _getViewPermissionDescription(User user) {
    switch (user.role) {
      case UserRole.adminGlobal:
        return 'Voir tous les appareils';
      case UserRole.adminPays:
        return 'Voir les appareils du ${user.countryCode}';
      case UserRole.adminDepartement:
        return 'Voir les appareils du département ${user.departmentCode}';
      case UserRole.client:
        return 'Aucun accès';
    }
  }

  String _getModifyPermissionDescription(User user) {
    switch (user.role) {
      case UserRole.adminGlobal:
        return 'Modifier tous les appareils';
      case UserRole.adminPays:
        return 'Modifier les appareils du ${user.countryCode}';
      case UserRole.adminDepartement:
        return 'Modifier les appareils du département ${user.departmentCode}';
      case UserRole.client:
        return 'Aucun accès';
    }
  }

  String _getAddPermissionDescription(User user) {
    switch (user.role) {
      case UserRole.adminGlobal:
        return 'Ajouter des appareils mondiaux';
      case UserRole.adminPays:
        return 'Ajouter des appareils au ${user.countryCode}';
      case UserRole.adminDepartement:
        return 'Ajouter des appareils au département ${user.departmentCode}';
      case UserRole.client:
        return 'Aucun accès';
    }
  }

  String _getDeletePermissionDescription(User user) {
    switch (user.role) {
      case UserRole.adminGlobal:
        return 'Supprimer tous les appareils';
      case UserRole.adminPays:
        return 'Supprimer les appareils du ${user.countryCode}';
      case UserRole.adminDepartement:
        return 'Supprimer les appareils du département ${user.departmentCode}';
      case UserRole.client:
        return 'Aucun accès';
    }
  }
}
