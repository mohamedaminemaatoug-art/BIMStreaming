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

  String tr(String key) => translate(key);

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
                      '${tr('profile_id_label')}: ${user.id}',
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
              tr('profile_permissions'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            _buildPermissionTile(
              icon: Icons.visibility,
              title: tr('profile_permission_view_title'),
              description: _getViewPermissionDescription(user),
              isDark: isDark,
            ),
            _buildPermissionTile(
              icon: Icons.edit,
              title: tr('profile_permission_modify_title'),
              description: _getModifyPermissionDescription(user),
              isDark: isDark,
              canAccess: user.role != UserRole.client,
            ),
            _buildPermissionTile(
              icon: Icons.add_circle,
              title: tr('profile_permission_add_title'),
              description: _getAddPermissionDescription(user),
              isDark: isDark,
              canAccess: user.role != UserRole.client,
            ),
            _buildPermissionTile(
              icon: Icons.delete,
              title: tr('profile_permission_delete_title'),
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
                        Text(
                          tr('profile_region_info'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (user.countryCode != null)
                          _buildInfoTile(
                            tr('profile_country_label'),
                            user.countryCode!,
                            isDark,
                          ),
                        if (user.departmentCode != null)
                          _buildInfoTile(
                            tr('profile_department_label'),
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
                    title: Text(tr('logout_confirm_title')),
                    content: Text(tr('logout_confirm_message')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('btn_cancel')),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onLogout();
                        },
                        child: Text(
                          tr('btn_disconnect'),
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout),
              label: Text(tr('btn_disconnect')),
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
        return tr('profile_view_all_devices');
      case UserRole.adminPays:
        return '${tr('profile_view_country_devices')} ${user.countryCode ?? ''}';
      case UserRole.adminDepartement:
        return '${tr('profile_view_department_devices')} ${user.departmentCode ?? ''}';
      case UserRole.client:
        return tr('profile_no_access');
    }
  }

  String _getModifyPermissionDescription(User user) {
    switch (user.role) {
      case UserRole.adminGlobal:
        return tr('profile_modify_all_devices');
      case UserRole.adminPays:
        return '${tr('profile_modify_country_devices')} ${user.countryCode ?? ''}';
      case UserRole.adminDepartement:
        return '${tr('profile_modify_department_devices')} ${user.departmentCode ?? ''}';
      case UserRole.client:
        return tr('profile_no_access');
    }
  }

  String _getAddPermissionDescription(User user) {
    switch (user.role) {
      case UserRole.adminGlobal:
        return tr('profile_add_all_devices');
      case UserRole.adminPays:
        return '${tr('profile_add_country_devices')} ${user.countryCode ?? ''}';
      case UserRole.adminDepartement:
        return '${tr('profile_add_department_devices')} ${user.departmentCode ?? ''}';
      case UserRole.client:
        return tr('profile_no_access');
    }
  }

  String _getDeletePermissionDescription(User user) {
    switch (user.role) {
      case UserRole.adminGlobal:
        return tr('profile_delete_all_devices');
      case UserRole.adminPays:
        return '${tr('profile_delete_country_devices')} ${user.countryCode ?? ''}';
      case UserRole.adminDepartement:
        return '${tr('profile_delete_department_devices')} ${user.departmentCode ?? ''}';
      case UserRole.client:
        return tr('profile_no_access');
    }
  }
}
