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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xFF112432), Color(0xFF174058)]
                      : const [Color(0xFFE8F6FF), Color(0xFFD8EEFF)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF27536B)
                      : const Color(0xFFC2DCEE),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: const Color(0xFF0F8DCC),
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF112333),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tr('profile_id_label')}: ${user.id}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFFB9D2E3)
                                : const Color(0xFF4B6678),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _getRoleColor(user.role),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            user.role.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr('profile_permissions'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 14),
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
                user.role == UserRole.adminDepartement) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF132330) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF284051)
                        : const Color(0xFFDCE5EC),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('profile_region_info'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF182B38),
                      ),
                    ),
                    const SizedBox(height: 10),
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
              const SizedBox(height: 24),
            ],
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
                backgroundColor: const Color(0xFFC53A2E),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132330) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF284051) : const Color(0xFFDCE5EC),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: canAccess
                ? const Color(0xFF0EA271)
                : const Color(0xFFC53A2E),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A2D3B),
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFFA8C2D4)
                        : const Color(0xFF6A8190),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            canAccess ? Icons.check_circle : Icons.cancel,
            color: canAccess
                ? const Color(0xFF0EA271)
                : const Color(0xFFC53A2E),
          ),
        ],
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
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
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
