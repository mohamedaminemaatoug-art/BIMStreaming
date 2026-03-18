import 'dart:io' as io;
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bim_streaming/models/user_model.dart';
import 'package:bim_streaming/services/auth_service.dart';
import 'package:bim_streaming/services/signaling_client_service.dart';
import 'package:bim_streaming/screens/login_page.dart';
import 'package:bim_streaming/screens/user_profile_page.dart';
import 'package:bim_streaming/screens/remote_support_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && io.Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(const WindowOptions(), () async {});
  }
  runApp(const BimStreamingApp());
}

class BimStreamingApp extends StatefulWidget {
  const BimStreamingApp({super.key});

  @override
  State<BimStreamingApp> createState() => _BimStreamingAppState();
}

class _BimStreamingAppState extends State<BimStreamingApp> {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ThemeModeType _themeMode = ThemeModeType.dark;
  Lang _lang = Lang.en;
  int _pageIndex = 0;
  
  // Authentication
  User? _currentAuthenticatedUser;
  final AuthService _authService = AuthService();
  final SignalingClientService _signalingService = SignalingClientService();
  StreamSubscription<SignalEvent>? _signalSubscription;
  bool _isAuthenticated = false;
  bool _isSignalConnected = false;
  bool _showDemoUsers = false;
  
  bool _showAddDialog = false;
  String _dialogCountry = '';
  String _dialogDepartment = '';
  bool _showAddDeptDialog = false;
  String _deptDialogCountry = '';
  final String _sessionPassword = _generateSecurePassword();

  // User Management
  static const String _roleAdminPrincipal = 'Admin Principal';
  static const String _roleAdminPays = 'Admin Pays';
  static const String _roleAdminDepartement = 'Admin Département';
  static const String _roleUser = 'User';
  static const String _roleTechnicien = 'Technicien Informatique';
  static const String _principalAdminId = 'PADM001';
  String _principalAdminPassword = 'principal123';
  static const String _recoveryTestCode = '123456';

  String _userRole = _roleUser;
  String _currentUserId = '';
  String _currentUserDept = 'IT Département'; // Département courant si Admin Département
  String _currentUserCountry = '🇫🇷 France'; // Pays courant si Admin Pays
  
  // Mapping des codes pays vers les noms complets dans la structure
  final Map<String, String> _countryCodeToName = {
    'FR': '🇫🇷 France',
    'US': '🇺🇸 USA',
    'GB': '🇬🇧 UK',
    'DE': '🇩🇪 Germany',
    'TN': '🇹🇳 Tunisia',
  };

  // Mapping des codes département vers les noms complets dans la structure
  final Map<String, String> _departmentCodeToDeptName = {
    'IT': 'IT Département',
    'HR': 'HR Département',
    'Finance': 'Finance Département',
    'Marketing': 'Marketing Département',
    'Engineering': 'Engineering Département',
    'Operations': 'Operations Département',
    'Sales': 'Sales Département',
    'Development': 'Development Département',
    'Support': 'Support Département',
  };
  
  late Map<String, Map<String, dynamic>> _usersStructure;

  final List<String> _recentConnections = const [
    'Recent Connections...',
    'Office-Workstation',
    'Dev-Server-01',
    'MacBook-Pro-M4',
  ];

  String _selectedConnection = 'Recent Connections...';
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _newUserController = TextEditingController();
  final TextEditingController _newUserIdController = TextEditingController();
  final TextEditingController _newUserPasswordController = TextEditingController();
  final TextEditingController _newDeptNameController = TextEditingController();
  final TextEditingController _newDeptAdminIdController = TextEditingController();
  final TextEditingController _newDeptAdminPasswordController = TextEditingController();
  final TextEditingController _newDeptAdminNameController = TextEditingController();

  final List<String> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();

  final TextEditingController _commandController = TextEditingController();
  String _commandOutput = 'Command output will appear here...';
  final TextEditingController _authIdController = TextEditingController();
  final TextEditingController _authPasswordController = TextEditingController();
  final TextEditingController _recoveryCodeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  String _recoveryMaskedEmail = '';
  String _recoveryTargetId = '';
  bool _recoveryCodeVerified = false;
  final TextEditingController _deviceSearchController = TextEditingController();
  static const String _userTypeStandard = 'user';
  static const String _userTypeTechnician = 'technician';
  static const String _allFilterValue = '__all__';
  String _selectedCountryFilter = _allFilterValue;
  String _selectedDepartmentFilter = _allFilterValue;
  DeviceRoleFilter _selectedDeviceRoleFilter = DeviceRoleFilter.all;
  String _newUserType = _userTypeStandard;
  final Set<String> _collapsedCountries = <String>{};
  final Set<String> _collapsedDepartments = <String>{};

  String _departmentCollapseKey(String country, String department) => '$country::$department';

  bool _isCountryCollapsed(String country) => _collapsedCountries.contains(country);

  bool _isDepartmentCollapsed(String country, String department) {
    return _collapsedDepartments.contains(_departmentCollapseKey(country, department));
  }

  void _toggleCountryCollapse(String country) {
    setState(() {
      if (_collapsedCountries.contains(country)) {
        _collapsedCountries.remove(country);
      } else {
        _collapsedCountries.add(country);
      }
    });
  }

  void _toggleDepartmentCollapse(String country, String department) {
    final key = _departmentCollapseKey(country, department);
    setState(() {
      if (_collapsedDepartments.contains(key)) {
        _collapsedDepartments.remove(key);
      } else {
        _collapsedDepartments.add(key);
      }
    });
  }

  SupportTab _supportTab = SupportTab.chat;
  bool _isSupportVideoExpanded = false;

  @override
  void initState() {
    super.initState();
    _initializeUsersStructure();
    _loadPreferences();
    _initializeGuestUser();
  }

  void _initializeGuestUser() {
    // Start in unauthenticated mode so LoginPage is shown first.
    _currentAuthenticatedUser = null;
    _isAuthenticated = false;
    _userRole = _roleUser;
    _currentUserId = '';
    _currentUserDept = 'IT Département';
    _currentUserCountry = '🇫🇷 France';
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('app_lang');
    final savedTheme = prefs.getString('app_theme');

    if (!mounted) return;

    setState(() {
      if (savedLang == Lang.fr.name) {
        _lang = Lang.fr;
      } else if (savedLang == Lang.en.name) {
        _lang = Lang.en;
      }

      if (savedTheme == ThemeModeType.light.name) {
        _themeMode = ThemeModeType.light;
      } else if (savedTheme == ThemeModeType.dark.name) {
        _themeMode = ThemeModeType.dark;
      }
    });
  }

  Future<void> _setLanguage(Lang value) async {
    setState(() => _lang = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang', value.name);
  }

  Future<void> _setThemeMode(ThemeModeType value) async {
    setState(() => _themeMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', value.name);
  }

  List<String> _countryFilterItems() {
    // Tous les rôles voient tous les pays dans les filtres
    return [_allFilterValue, ..._usersStructure.keys];
  }

  List<String> _departmentFilterItems() {
    final departmentNames = <String>{};
    final countries = _selectedCountryFilter == _allFilterValue
        ? _usersStructure.entries
        : _usersStructure.entries.where((entry) => entry.key == _selectedCountryFilter);

    for (final countryEntry in countries) {
      for (final deptEntry in countryEntry.value.entries) {
        if (deptEntry.key != 'countryAdmin') {
          departmentNames.add(deptEntry.key);
        }
      }
    }

    final sortedDepartments = departmentNames.toList()..sort();
    return [_allFilterValue, ...sortedDepartments];
  }

  bool _matchesUserSearch({
    required String country,
    required String department,
    required Map<String, String> user,
  }) {
    final query = _deviceSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;

    final name = (user['name'] ?? '').toLowerCase();
    final id = (user['id'] ?? '').toLowerCase();
    final role = (user['role'] ?? _userTypeStandard).toLowerCase();
    final countryText = country.toLowerCase();
    final departmentText = department.toLowerCase();
    final matchesRole = role.contains(query) ||
      (role == _userTypeTechnician && ('technicien'.contains(query) || 'technician'.contains(query))) ||
      (role == _userTypeStandard && ('utilisateur'.contains(query) || 'user'.contains(query)));
    return name.contains(query) || id.contains(query) || countryText.contains(query) || departmentText.contains(query) || matchesRole;
  }

  Map<String, Map<String, dynamic>> _getFilteredUsersStructure() {
    // Tous les rôles voient toute la structure - pas de filtrage basé sur les rôles
    // Les restrictions sont appliquées au niveau des actions (ajouter, modifier, supprimer)
    final baseStructure = _usersStructure;
    
    // Appliquer les filtres de recherche et sélection
    final query = _deviceSearchController.text.trim();
    final hasSearch = query.isNotEmpty;
    final hasCountry = _selectedCountryFilter != _allFilterValue;
    final hasDepartment = _selectedDepartmentFilter != _allFilterValue;
    final hasRole = _selectedDeviceRoleFilter != DeviceRoleFilter.all;

    if (!hasSearch && !hasCountry && !hasDepartment && !hasRole) {
      return baseStructure;
    }

    final result = <String, Map<String, dynamic>>{};

    for (final countryEntry in baseStructure.entries) {
      final countryName = countryEntry.key;
      final countryData = countryEntry.value;

      if (hasCountry && countryName != _selectedCountryFilter) {
        continue;
      }

      final filteredCountryData = <String, dynamic>{};
      final countryAdminRaw = countryData['countryAdmin'];
      if (countryAdminRaw is Map) {
        final countryAdmin = Map<String, String>.from(countryAdminRaw);
        final includeCountryAdmin = _selectedDeviceRoleFilter == DeviceRoleFilter.all ||
            _selectedDeviceRoleFilter == DeviceRoleFilter.countryAdmin;
        if (includeCountryAdmin && _matchesUserSearch(country: countryName, department: '', user: countryAdmin)) {
          filteredCountryData['countryAdmin'] = countryAdmin;
        }
      }

      for (final departmentEntry in countryData.entries) {
        if (departmentEntry.key == 'countryAdmin') continue;

        final departmentName = departmentEntry.key;
        if (hasDepartment && departmentName != _selectedDepartmentFilter) {
          continue;
        }

        final rawDepartmentData = departmentEntry.value;
        if (rawDepartmentData is! Map) continue;

        final departmentData = Map<String, dynamic>.from(rawDepartmentData);
        final admin = Map<String, String>.from(departmentData['admin'] as Map);
        final users = (departmentData['users'] as List)
            .map((user) => Map<String, String>.from(user as Map))
            .toList();

        final includeDeptAdmin = _selectedDeviceRoleFilter == DeviceRoleFilter.all ||
            _selectedDeviceRoleFilter == DeviceRoleFilter.departmentAdmin;
        final includeStandardUsers = _selectedDeviceRoleFilter == DeviceRoleFilter.all ||
          _selectedDeviceRoleFilter == DeviceRoleFilter.user;
        final includeTechnicians = _selectedDeviceRoleFilter == DeviceRoleFilter.all ||
          _selectedDeviceRoleFilter == DeviceRoleFilter.technician;

        final adminMatches = includeDeptAdmin && _matchesUserSearch(
          country: countryName,
          department: departmentName,
          user: admin,
        );

        final filteredUsers = (includeStandardUsers || includeTechnicians)
            ? users
                .where(
                  (user) {
                    final userRole = user['role'] ?? _userTypeStandard;
                    final roleAllowed = (userRole == _userTypeTechnician && includeTechnicians) ||
                        (userRole != _userTypeTechnician && includeStandardUsers);
                    if (!roleAllowed) return false;
                    return _matchesUserSearch(
                      country: countryName,
                      department: departmentName,
                      user: user,
                    );
                  },
                )
                .toList()
            : <Map<String, String>>[];

        if (adminMatches || filteredUsers.isNotEmpty) {
          filteredCountryData[departmentName] = {
            'admin': admin,
            'users': filteredUsers,
            'showAdmin': includeDeptAdmin,
          };
        }
      }

      final hasCountryAdmin = filteredCountryData.containsKey('countryAdmin');
      final hasDepartmentData = filteredCountryData.keys.any((key) => key != 'countryAdmin');
      if (hasCountryAdmin || hasDepartmentData) {
        result[countryName] = filteredCountryData;
      }
    }

    return result;
  }

  String _deviceRoleFilterLabel(DeviceRoleFilter value) {
    switch (value) {
      case DeviceRoleFilter.all:
        return t['filter_all_roles']!;
      case DeviceRoleFilter.countryAdmin:
        return t['role_country_admin']!;
      case DeviceRoleFilter.departmentAdmin:
        return t['role_department_admin']!;
      case DeviceRoleFilter.user:
        return t['role_user']!;
      case DeviceRoleFilter.technician:
        return t['role_it_technician']!;
    }
  }

  String _userTypeLabel(String type) {
    return type == _userTypeTechnician ? t['role_it_technician']! : t['role_user']!;
  }

  String _appRoleLabel(String role) {
    switch (role) {
      case _roleAdminPrincipal:
        return t['role_admin_principal']!;
      case _roleAdminPays:
        return t['role_country_admin']!;
      case _roleAdminDepartement:
        return t['role_department_admin']!;
      case _roleTechnicien:
        return t['role_it_technician']!;
      default:
        return t['role_user']!;
    }
  }

  String _buildRecoveryEmail(String id) {
    return '${id.toLowerCase()}@mail.com';
  }

  String _maskEmail(String email) {
    if (email.length <= 10) return '***';
    final prefix = email.substring(0, 3);
    final suffix = email.substring(email.length - 7);
    return '$prefix**********$suffix';
  }

  bool _accountExistsForId(String id) {
    if (id == _principalAdminId) return true;

    for (final countryEntry in _usersStructure.entries) {
      final countryAdmin = Map<String, String>.from(countryEntry.value['countryAdmin']);
      if (countryAdmin['id'] == id) return true;

      for (final deptEntry in countryEntry.value.entries) {
        if (deptEntry.key == 'countryAdmin') continue;
        final admin = Map<String, String>.from(deptEntry.value['admin']);
        if (admin['id'] == id) return true;

        final users = List<Map<String, String>>.from(
          (deptEntry.value['users'] as List).map((u) => Map<String, String>.from(u)),
        );
        if (users.any((user) => user['id'] == id)) return true;
      }
    }

    return false;
  }

  void _forgotPassword() {
    final id = _authIdController.text.trim();
    if (id.isEmpty) {
      _showStubMessage(t['recovery_enter_id_first']!);
      return;
    }

    if (!_accountExistsForId(id)) {
      _showStubMessage(t['auth_invalid_credentials']!);
      return;
    }

    final email = _buildRecoveryEmail(id);
    setState(() {
      _recoveryTargetId = id;
      _recoveryMaskedEmail = _maskEmail(email);
      _recoveryCodeVerified = false;
      _recoveryCodeController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    });
    _showStubMessage('${t['recovery_sent_to']!} $_recoveryMaskedEmail');
  }

  void _verifyRecoveryCode() {
    if (_recoveryCodeController.text.trim() != _recoveryTestCode) {
      _showStubMessage(t['recovery_invalid_code']!);
      return;
    }
    setState(() => _recoveryCodeVerified = true);
    _showStubMessage(t['recovery_code_valid']!);
  }

  bool _updatePasswordForId(String id, String newPassword) {
    if (id == _principalAdminId) {
      _principalAdminPassword = newPassword;
      return true;
    }

    for (final countryEntry in _usersStructure.entries) {
      final countryName = countryEntry.key;
      final countryData = countryEntry.value;

      final countryAdmin = Map<String, String>.from(countryData['countryAdmin']);
      if (countryAdmin['id'] == id) {
        setState(() {
          _usersStructure[countryName]!['countryAdmin'] = {
            ...countryAdmin,
            'password': newPassword,
          };
        });
        return true;
      }

      for (final deptEntry in countryData.entries) {
        if (deptEntry.key == 'countryAdmin') continue;
        final deptName = deptEntry.key;
        final deptData = Map<String, dynamic>.from(deptEntry.value);

        final admin = Map<String, String>.from(deptData['admin']);
        if (admin['id'] == id) {
          setState(() {
            _usersStructure[countryName]![deptName]!['admin'] = {
              ...admin,
              'password': newPassword,
            };
          });
          return true;
        }

        final users = List<Map<String, String>>.from(
          (deptData['users'] as List).map((u) => Map<String, String>.from(u)),
        );
        final userIndex = users.indexWhere((user) => user['id'] == id);
        if (userIndex >= 0) {
          users[userIndex] = {
            ...users[userIndex],
            'password': newPassword,
          };
          setState(() {
            _usersStructure[countryName]![deptName]!['users'] = users;
          });
          return true;
        }
      }
    }

    return false;
  }

  void _submitPasswordReset() {
    final password = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.isEmpty || confirmPassword.isEmpty) {
      _showStubMessage(t['recovery_fill_passwords']!);
      return;
    }

    if (password != confirmPassword) {
      _showStubMessage(t['recovery_password_mismatch']!);
      return;
    }

    if (_recoveryTargetId.isEmpty) {
      _showStubMessage(t['auth_invalid_credentials']!);
      return;
    }

    final updated = _updatePasswordForId(_recoveryTargetId, password);
    if (!updated) {
      _showStubMessage(t['auth_invalid_credentials']!);
      return;
    }

    setState(() {
      _authPasswordController.text = password;
      _recoveryMaskedEmail = '';
      _recoveryTargetId = '';
      _recoveryCodeVerified = false;
      _recoveryCodeController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    });
    _showStubMessage(t['recovery_password_updated']!);
  }

  bool _authenticate() {
    final id = _authIdController.text.trim();
    final password = _authPasswordController.text.trim();

    if (id.isEmpty || password.isEmpty) {
      _showStubMessage(t['auth_fill_all_fields']!);
      return false;
    }

    if (id == _principalAdminId && password == _principalAdminPassword) {
      setState(() {
        _userRole = _roleAdminPrincipal;
        _currentUserId = id;
      });
      _showStubMessage(t['auth_success']!);
      return true;
    }

    for (final entry in _usersStructure.entries) {
      final countryAdmin = Map<String, String>.from(entry.value['countryAdmin']);
      if (countryAdmin['id'] == id && countryAdmin['password'] == password) {
        setState(() {
          _userRole = _roleAdminPays;
          _currentUserId = id;
          _currentUserCountry = entry.key;
        });
        _showStubMessage(t['auth_success']!);
        return true;
      }
    }

    for (final countryEntry in _usersStructure.entries) {
      for (final deptEntry in countryEntry.value.entries) {
        if (deptEntry.key == 'countryAdmin') continue;
        final admin = Map<String, String>.from(deptEntry.value['admin']);
        if (admin['id'] == id && admin['password'] == password) {
          setState(() {
            _userRole = _roleAdminDepartement;
            _currentUserId = id;
            _currentUserCountry = countryEntry.key;
            _currentUserDept = deptEntry.key;
          });
          _showStubMessage(t['auth_success']!);
          return true;
        }
      }
    }

    for (final countryEntry in _usersStructure.entries) {
      for (final deptEntry in countryEntry.value.entries) {
        if (deptEntry.key == 'countryAdmin') continue;
        final users = List<Map<String, String>>.from(
          (deptEntry.value['users'] as List).map((u) => Map<String, String>.from(u)),
        );
        for (final user in users) {
          if (user['id'] != id || user['password'] != password) continue;
          final userType = user['role'] ?? _userTypeStandard;
          final isTechnician = userType == _userTypeTechnician;

          setState(() {
            _userRole = isTechnician ? _roleTechnicien : _roleUser;
            _currentUserId = id;
            _currentUserCountry = countryEntry.key;
            _currentUserDept = deptEntry.key;
            // Update the authenticated user object with AuthService
            _currentAuthenticatedUser = User(
              id: id,
              name: user['name'] ?? id,
              password: password,
              role: UserRole.client,
              countryCode: countryEntry.key.replaceAll(RegExp(r'[^\w]'), ''),
              departmentCode: deptEntry.key,
            );
          });
          _showStubMessage(t['auth_success']!);
          return true;
        }
      }
    }

    _showStubMessage(t['auth_invalid_credentials']!);
    return false;
  }

  Future<void> _authenticateWithAuthService() async {
    final id = _authIdController.text.trim();
    final password = _authPasswordController.text.trim();

    if (id.isEmpty || password.isEmpty) {
      _showStubMessage(t['auth_fill_all_fields']!);
      return;
    }

    final result = await _authService.login(id, password);

    if (!mounted) return;

    if (result.success && result.user != null) {
      setState(() {
        _currentAuthenticatedUser = result.user;
        _isAuthenticated = true;
        _pageIndex = 0;
        _userRole = _mapUserRoleToString(result.user!.role);
        _currentUserId = result.user!.id;
        if (result.user!.countryCode != null && _countryCodeToName.containsKey(result.user!.countryCode)) {
          _currentUserCountry = _countryCodeToName[result.user!.countryCode]!;
        }
        if (result.user!.departmentCode != null && _departmentCodeToDeptName.containsKey(result.user!.departmentCode)) {
          _currentUserDept = _departmentCodeToDeptName[result.user!.departmentCode]!;
        }
      });
      _showStubMessage(result.message);
      _authIdController.clear();
      _authPasswordController.clear();
      _connectSignalingForCurrentUser();
    } else {
      _showStubMessage(result.message);
    }
  }

  void _initializeUsersStructure() {
    _usersStructure = {
      '🇫🇷 France': {
        'countryAdmin': {'id': 'CADM001', 'password': 'countryadmin', 'name': 'François Durand'},
        'IT Département': {
          'admin': {'id': 'ADM001', 'password': 'admin123', 'name': 'Alice Johnson'},
          'users': [
            {'id': 'USR001', 'password': 'pass123', 'name': 'Marie Dupont'},
            {'id': 'USR002', 'password': 'pass123', 'name': 'Jean Petit'},
            {'id': 'USR003', 'password': 'pass123', 'name': 'Sophie Martin', 'role': _userTypeTechnician},
          ],
        },
        'HR Département': {
          'admin': {'id': 'ADM002', 'password': 'admin123', 'name': 'Bob Smith'},
          'users': [
            {'id': 'USR004', 'password': 'pass123', 'name': 'Paul Bernard'},
            {'id': 'USR005', 'password': 'pass123', 'name': 'Luc Blanc'},
          ],
        },
      },
      '🇺🇸 USA': {
        'countryAdmin': {'id': 'CADM002', 'password': 'countryadmin', 'name': 'Robert Williams'},
        'Finance Département': {
          'admin': {'id': 'ADM003', 'password': 'admin123', 'name': 'Carol White'},
          'users': [
            {'id': 'USR006', 'password': 'pass123', 'name': 'Michel Girard'},
            {'id': 'USR007', 'password': 'pass123', 'name': 'Anne Moreau'},
            {'id': 'USR008', 'password': 'pass123', 'name': 'David Lefevre'},
          ],
        },
        'Marketing Département': {
          'admin': {'id': 'ADM004', 'password': 'admin123', 'name': 'David Brown'},
          'users': [
            {'id': 'USR009', 'password': 'pass123', 'name': 'Isabelle Fournier'},
            {'id': 'USR010', 'password': 'pass123', 'name': 'Pierre Fontaine'},
          ],
        },
      },
      '🇬🇧 UK': {
        'countryAdmin': {'id': 'CADM003', 'password': 'countryadmin', 'name': 'Oliver Smith'},
        'Engineering Département': {
          'admin': {'id': 'ADM005', 'password': 'admin123', 'name': 'Emma Wilson'},
          'users': [
            {'id': 'USR011', 'password': 'pass123', 'name': 'John Doe'},
            {'id': 'USR012', 'password': 'pass123', 'name': 'Jane Smith'},
            {'id': 'USR013', 'password': 'pass123', 'name': 'Robert Taylor'},
          ],
        },
        'Operations Département': {
          'admin': {'id': 'ADM006', 'password': 'admin123', 'name': 'Frank Miller'},
          'users': [
            {'id': 'USR014', 'password': 'pass123', 'name': 'Sarah Johnson'},
            {'id': 'USR015', 'password': 'pass123', 'name': 'Michael Brown'},
          ],
        },
      },
      '🇩🇪 Germany': {
        'countryAdmin': {'id': 'CADM004', 'password': 'countryadmin', 'name': 'Hans Schmidt'},
        'Sales Département': {
          'admin': {'id': 'ADM007', 'password': 'admin123', 'name': 'Greta Hansen'},
          'users': [
            {'id': 'USR016', 'password': 'pass123', 'name': 'Klaus Mueller'},
            {'id': 'USR017', 'password': 'pass123', 'name': 'Anna Weber'},
            {'id': 'USR018', 'password': 'pass123', 'name': 'Otto Fischer'},
          ],
        },
      },
      '🇹🇳 Tunisia': {
        'countryAdmin': {'id': 'CADM005', 'password': 'countryadmin', 'name': 'Mohamed Trabelsi'},
        'Development Département': {
          'admin': {'id': 'ADM008', 'password': 'admin123', 'name': 'Hana Ben Ahmed'},
          'users': [
            {'id': 'USR019', 'password': 'pass123', 'name': 'Karim Saidi'},
            {'id': 'USR020', 'password': 'pass123', 'name': 'Leila Amdouni'},
            {'id': 'USR021', 'password': 'pass123', 'name': 'Noor Zahra'},
          ],
        },
        'Support Département': {
          'admin': {'id': 'ADM009', 'password': 'admin123', 'name': 'Imed Karray'},
          'users': [
            {'id': 'USR022', 'password': 'pass123', 'name': 'Rania Ghazal'},
            {'id': 'USR023', 'password': 'pass123', 'name': 'Sami Dhahri'},
          ],
        },
      },
    };
  }

  void _addUser(
    String country,
    String department,
    String userId,
    String userPassword,
    String userName,
    bool isAdmin,
    String userType,
  ) {
    // Vérifier les permissions
    bool hasPermission = false;
    if (_userRole == _roleAdminPrincipal) {
      hasPermission = true; // Admin Principal peut tout faire
    } else if (_userRole == _roleAdminPays && _currentUserCountry == country) {
      hasPermission = true; // Admin Pays peut gérer tous les départements de son pays
    } else if (_userRole == _roleAdminDepartement && _currentUserDept == department && _currentUserCountry == country) {
      hasPermission = !isAdmin; // Admin Département peut ajouter seulement des utilisateurs, pas des admins
    }
    
    if (!hasPermission) {
      _showStubMessage('Vous n\'avez pas les permissions pour cette action');
      return;
    }

    setState(() {
      if (isAdmin) {
        _usersStructure[country]![department]!['admin'] = {'id': userId, 'password': userPassword, 'name': userName};
      } else {
        final usersList = List<Map<String, String>>.from(
          (_usersStructure[country]![department]!['users'] as List).map((u) => Map<String, String>.from(u))
        );
        usersList.add({'id': userId, 'password': userPassword, 'name': userName, 'role': userType});
        _usersStructure[country]![department]!['users'] = usersList;
      }
    });
    _showStubMessage('Utilisateur $userName ajouté avec succès!');
  }

  void _deleteUser(String country, String department, String userId) {
    // Vérifier les permissions
    bool hasPermission = false;
    if (_userRole == _roleAdminPrincipal) {
      hasPermission = true; // Admin Principal peut tout faire
    } else if (_userRole == _roleAdminPays && _currentUserCountry == country) {
      hasPermission = true; // Admin Pays peut gérer tous les départements de son pays
    } else if (_userRole == _roleAdminDepartement && _currentUserDept == department && _currentUserCountry == country) {
      hasPermission = true; // Admin Département peut supprimer les utilisateurs de son département
    }
    
    if (!hasPermission) {
      _showStubMessage('Vous n\'avez pas les permissions pour cette action');
      return;
    }

    setState(() {
      final usersList = List<Map<String, String>>.from(
        (_usersStructure[country]![department]!['users'] as List).map((u) => Map<String, String>.from(u))
      );
      usersList.removeWhere((user) => user['id'] == userId);
      _usersStructure[country]![department]!['users'] = usersList;
    });
    _showStubMessage('Utilisateur supprimé avec succès!');
  }

  void _showAddUserDialog(String country, String department) {
    setState(() {
      _dialogCountry = country;
      _dialogDepartment = department;
      _newUserIdController.clear();
      _newUserPasswordController.clear();
      _newUserController.clear();
      _newUserType = _userTypeStandard;
      _showAddDialog = true;
    });
  }

  void _closeAddUserDialog() {
    setState(() {
      _showAddDialog = false;
    });
  }

  void _submitAddUser() {
    if (_newUserIdController.text.trim().isNotEmpty && 
        _newUserPasswordController.text.trim().isNotEmpty &&
        _newUserController.text.trim().isNotEmpty) {
      _addUser(
        _dialogCountry, 
        _dialogDepartment, 
        _newUserIdController.text.trim(),
        _newUserPasswordController.text.trim(), 
        _newUserController.text.trim(), 
        false,
        _newUserType,
      );
      _closeAddUserDialog();
    } else {
      _showStubMessage('Veuillez remplir tous les champs');
    }
  }

  void _openAddDeptDialog(String country) {
    setState(() {
      _deptDialogCountry = country;
      _newDeptNameController.clear();
      _newDeptAdminIdController.clear();
      _newDeptAdminPasswordController.clear();
      _newDeptAdminNameController.clear();
      _showAddDeptDialog = true;
    });
  }

  void _closeAddDeptDialog() {
    setState(() {
      _showAddDeptDialog = false;
    });
  }

  void _submitAddDept() {
    if (_newDeptNameController.text.trim().isNotEmpty &&
        _newDeptAdminIdController.text.trim().isNotEmpty &&
        _newDeptAdminPasswordController.text.trim().isNotEmpty &&
        _newDeptAdminNameController.text.trim().isNotEmpty) {
      _addDepartment(
        _deptDialogCountry,
        _newDeptNameController.text.trim(),
        _newDeptAdminIdController.text.trim(),
        _newDeptAdminPasswordController.text.trim(),
        _newDeptAdminNameController.text.trim()
      );
      _closeAddDeptDialog();
    } else {
      _showStubMessage('Veuillez remplir tous les champs');
    }
  }

  void _addDepartment(String country, String deptName, String adminId, String adminPassword, String adminName) {
    // Vérifier les permissions
    bool hasPermission = false;
    if (_userRole == _roleAdminPrincipal) {
      hasPermission = true; // Admin Principal peut créer des départements partout
    } else if (_userRole == _roleAdminPays && _currentUserCountry == country) {
      hasPermission = true; // Admin Pays peut créer des départements dans son pays
    }
    // Admin Département ne peut pas créer de départements
    
    if (!hasPermission) {
      _showStubMessage('Vous n\'avez pas les permissions pour créer un département');
      return;
    }

    setState(() {
      _usersStructure[country]![deptName] = {
        'admin': {'id': adminId, 'password': adminPassword, 'name': adminName},
        'users': [],
      };
    });
    _showStubMessage('Département $deptName créé avec succès!');
  }

  void _promoteToAdmin(String country, String department, Map<String, String> user) {
    // Vérifier les permissions
    bool hasPermission = false;
    if (_userRole == _roleAdminPrincipal) {
      hasPermission = true; // Admin Principal peut promouvoir partout
    } else if (_userRole == _roleAdminPays && _currentUserCountry == country) {
      hasPermission = true; // Admin Pays peut promouvoir dans son pays
    }
    // Admin Département ne peut pas promouvoir
    
    if (!hasPermission) {
      _showStubMessage('Vous n\'avez pas les permissions pour promouvoir un utilisateur');
      return;
    }

    setState(() {
      // Récupérer l'ancien admin
      final oldAdmin = Map<String, String>.from(_usersStructure[country]![department]!['admin']);
      
      // Promouvoir l'utilisateur en admin
      _usersStructure[country]![department]!['admin'] = user;
      
      // Rétrograder l'ancien admin en utilisateur normal
      final usersList = List<Map<String, String>>.from(
        (_usersStructure[country]![department]!['users'] as List).map((u) => Map<String, String>.from(u))
      );
      usersList.removeWhere((u) => u['id'] == user['id']);
      usersList.add(oldAdmin);
      _usersStructure[country]![department]!['users'] = usersList;
    });
    _showStubMessage('${user['name']} est maintenant admin de $department');
  }

  void _deleteDepartment(String country, String deptName) {
    // Vérifier les permissions
    bool hasPermission = false;
    if (_userRole == _roleAdminPrincipal) {
      hasPermission = true; // Admin Principal peut supprimer partout
    } else if (_userRole == _roleAdminPays && _currentUserCountry == country) {
      hasPermission = true; // Admin Pays peut supprimer des départements de son pays
    }
    // Admin Département ne peut pas supprimer des départements
    
    if (!hasPermission) {
      _showStubMessage('Vous n\'avez pas les permissions pour supprimer un département');
      return;
    }

    setState(() {
      _usersStructure[country]!.remove(deptName);
    });
    _showStubMessage('Département $deptName supprimé avec succès!');
  }

  void _demoteToUser(String country, String department) {
    // Pour rétrograder un admin, on doit avoir un utilisateur qui le remplace
    _showStubMessage('Sélectionnez un utilisateur pour remplacer l\'admin actuel');
  }

  Widget _buildAddUserDialog() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeAddUserDialog,
        child: Container(
          color: Colors.black54,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Prevent closing when tapping inside dialog
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['add_user_title']!, style: TextStyle(color: c.textP, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _newUserIdController,
                      autofocus: true,
                      style: TextStyle(color: c.textP),
                      decoration: InputDecoration(
                        labelText: 'ID',
                        labelStyle: TextStyle(color: c.textS),
                        hintText: 'Ex: USR024',
                        hintStyle: TextStyle(color: c.textS),
                        filled: true,
                        fillColor: c.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newUserPasswordController,
                      obscureText: true,
                      style: TextStyle(color: c.textP),
                      decoration: InputDecoration(
                        labelText: t['password']!,
                        labelStyle: TextStyle(color: c.textS),
                        hintText: t['password_hint']!,
                        hintStyle: TextStyle(color: c.textS),
                        filled: true,
                        fillColor: c.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newUserController,
                      style: TextStyle(color: c.textP),
                      decoration: InputDecoration(
                        labelText: t['name']!,
                        labelStyle: TextStyle(color: c.textS),
                        hintText: t['full_name_hint']!,
                        hintStyle: TextStyle(color: c.textS),
                        filled: true,
                        fillColor: c.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.accent),
                        ),
                      ),
                      onSubmitted: (_) => _submitAddUser(),
                    ),
                    const SizedBox(height: 12),
                    Text(t['user_role_field']!, style: TextStyle(color: c.textS, fontSize: 12)),
                    const SizedBox(height: 6),
                    _styledDropdown<String>(
                      value: _newUserType,
                      items: const [_userTypeStandard, _userTypeTechnician],
                      labelBuilder: _userTypeLabel,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _newUserType = value);
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _closeAddUserDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(t['btn_cancel']!, style: TextStyle(color: c.textS)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _submitAddUser,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(t['btn_add']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddDeptDialog() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeAddDeptDialog,
        child: Container(
          color: Colors.black54,
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 450,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Créer un nouveau département', style: TextStyle(color: c.textP, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _newDeptNameController,
                      autofocus: true,
                      style: TextStyle(color: c.textP),
                      decoration: InputDecoration(
                        labelText: 'Nom du département',
                        labelStyle: TextStyle(color: c.textS),
                        hintText: 'Ex: IT Département',
                        hintStyle: TextStyle(color: c.textS),
                        filled: true,
                        fillColor: c.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Admin du département', style: TextStyle(color: c.textP, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _newDeptAdminIdController,
                      style: TextStyle(color: c.textP),
                      decoration: InputDecoration(
                        labelText: 'ID Admin',
                        labelStyle: TextStyle(color: c.textS),
                        hintText: 'Ex: ADM010',
                        hintStyle: TextStyle(color: c.textS),
                        filled: true,
                        fillColor: c.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newDeptAdminPasswordController,
                      obscureText: true,
                      style: TextStyle(color: c.textP),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe Admin',
                        labelStyle: TextStyle(color: c.textS),
                        hintText: 'Mot de passe',
                        hintStyle: TextStyle(color: c.textS),
                        filled: true,
                        fillColor: c.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newDeptAdminNameController,
                      style: TextStyle(color: c.textP),
                      decoration: InputDecoration(
                        labelText: 'Nom Admin',
                        labelStyle: TextStyle(color: c.textS),
                        hintText: 'Nom complet',
                        hintStyle: TextStyle(color: c.textS),
                        filled: true,
                        fillColor: c.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: c.accent),
                        ),
                      ),
                      onSubmitted: (_) => _submitAddDept(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _closeAddDeptDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(t['btn_cancel']!, style: TextStyle(color: c.textS)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _submitAddDept,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(t['btn_create']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _generateSecurePassword() {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  AppColors get c => _themeMode == ThemeModeType.dark ? AppColors.dark : AppColors.light;
  Map<String, String> get t => _translations[_lang]!;

  Future<bool> _openSupportSession() async {
    final targetAccountId = _idController.text.trim();
    if (targetAccountId.isEmpty) {
      _showStubMessage(t['remote_account_required']!);
      return false;
    }

    return _requestConnectionToUser(
      targetId: targetAccountId,
      targetName: targetAccountId,
    );
  }

  Future<bool> _requestConnectionToUser({
    required String targetId,
    required String targetName,
  }) async {
    if (_currentUserId.isEmpty) {
      _showStubMessage(t['auth_fill_all_fields']!);
      return false;
    }
    if (!_isSignalConnected) {
      _showStubMessage(t['signaling_offline']!);
      return false;
    }

    final result = await _signalingService.requestSession(
      fromUserId: _currentUserId,
      fromName: _currentAuthenticatedUser?.name ?? _currentUserId,
      toUserId: targetId,
    );

    if (!mounted) return false;

    if (result['success'] != true) {
      _showStubMessage((result['message'] ?? t['request_failed']!).toString());
      return false;
    }

    _showStubMessage(t['connection_request_sent']!.replaceAll('{name}', targetName));
    return true;
  }

  void _openSupportPageForPeer({
    required String peerId,
    required String peerName,
    required bool sendLocalScreen,
    String? sessionId,
  }) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => RemoteSupportPage(
          deviceName: peerName,
          deviceId: peerId,
          sendLocalScreen: sendLocalScreen,
          onExitToRemoteControl: () {
            if (!mounted) return;
            setState(() => _pageIndex = 0);
          },
          sessionId: sessionId,
          currentUserId: _currentUserId,
          signalingService: _signalingService,
          isDarkMode: _themeMode == ThemeModeType.dark,
          translate: (key) => t[key] ?? key,
        ),
      ),
    );
  }

  Future<void> _handleDeviceUserTap(Map<String, String> user) async {
    final targetId = user['id'] ?? '';
    final targetName = user['name'] ?? targetId;
    if (targetId.isEmpty) return;
    if (!mounted) return;

    if (targetId == _currentUserId) {
      _showStubMessage(t['device_pick_another_user']!);
      return;
    }

    await _requestConnectionToUser(targetId: targetId, targetName: targetName);
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _chatMessages.add(text);
      _chatController.clear();
    });
  }

  void _executeCommand() {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;
    setState(() {
      _commandOutput = '> $cmd\nCommand executed successfully.';
      _commandController.clear();
    });
  }

  void _showStubMessage(String text) {
    _scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _connectSignalingForCurrentUser() async {
    if (_currentUserId.trim().isEmpty) {
      return;
    }

    await _signalSubscription?.cancel();
    final connected = await _signalingService.connect(userId: _currentUserId);
    if (!mounted) return;

    setState(() => _isSignalConnected = connected);
    if (!connected) {
      _showStubMessage(t['signaling_offline']!);
      return;
    }

    _signalSubscription = _signalingService.events.listen(_handleSignalEvent);
  }

  Future<void> _handleSignalEvent(SignalEvent event) async {
    if (!mounted) return;

    if (event.type == 'connection_request') {
      final sessionId = (event.data['session_id'] ?? '').toString();
      final fromUserId = (event.data['from'] ?? '').toString();
      final payload = event.data['payload'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(event.data['payload'] as Map<String, dynamic>)
          : <String, dynamic>{};
      final fromName = (payload['from_name'] ?? fromUserId).toString();
      if (sessionId.isEmpty || fromUserId.isEmpty) return;

      final dialogContext = _navigatorKey.currentContext;
      if (dialogContext == null) return;

      final accepted = await showDialog<bool>(
        context: dialogContext,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(t['connection_request_title']!),
          content: Text(t['incoming_connection_request']!.replaceAll('{name}', fromName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t['btn_reject']!),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t['btn_accept']!),
            ),
          ],
        ),
      );

      if (accepted == null) return;

      await _signalingService.respondSession(
        sessionId: sessionId,
        fromUserId: _currentUserId,
        toUserId: fromUserId,
        accepted: accepted,
      );

      if (accepted) {
        _openSupportPageForPeer(
          peerId: fromUserId,
          peerName: fromName,
          sendLocalScreen: true,
          sessionId: sessionId,
        );
      } else {
        _showStubMessage(t['connection_rejected']!);
      }
      return;
    }

    if (event.type == 'connection_accept') {
      final peerId = (event.data['from'] ?? '').toString();
      final sessionId = (event.data['session_id'] ?? '').toString();
      if (peerId.isEmpty) return;
      _showStubMessage(t['connection_accepted']!.replaceAll('{name}', peerId));
      _openSupportPageForPeer(
        peerId: peerId,
        peerName: peerId,
        sendLocalScreen: false,
        sessionId: sessionId.isEmpty ? null : sessionId,
      );
      return;
    }

    if (event.type == 'connection_reject') {
      final peerId = (event.data['from'] ?? '').toString();
      _showStubMessage(t['connection_rejected_by']!.replaceAll('{name}', peerId));
    }
  }

  @override
  void dispose() {
    _signalSubscription?.cancel();
    _signalingService.dispose();
    _idController.dispose();
    _passwordController.dispose();
    _chatController.dispose();
    _commandController.dispose();
    _authIdController.dispose();
    _authPasswordController.dispose();
    _recoveryCodeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newUserController.dispose();
    _newUserIdController.dispose();
    _newUserPasswordController.dispose();
    _newDeptNameController.dispose();
    _newDeptAdminIdController.dispose();
    _newDeptAdminPasswordController.dispose();
    _newDeptAdminNameController.dispose();
    _deviceSearchController.dispose();
    super.dispose();
  }

  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        final file = result.files.single;
        setState(() {
          _commandOutput = '> Upload: ${file.name}\nFile uploaded successfully at ${DateTime.now()}';
        });
        _showStubMessage('File ${file.name} uploaded successfully!');
      } else {
        _showStubMessage('Upload cancelled');
      }
    } catch (e) {
      _showStubMessage('Upload error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si l'utilisateur n'est pas authentifié, afficher la page de login
    if (!_isAuthenticated || _currentAuthenticatedUser == null) {
      return MaterialApp(
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _scaffoldMessengerKey,
        debugShowCheckedModeBanner: false,
        title: t['title']!,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('fr', 'FR'),
        ],
        theme: ThemeData(
          useMaterial3: true,
          brightness: _themeMode == ThemeModeType.dark ? Brightness.dark : Brightness.light,
        ),
        home: LoginPage(
          isDarkMode: _themeMode == ThemeModeType.dark,
          translate: (key) => t[key] ?? key,
          onLoginSuccess: (user) {
            setState(() {
              _currentAuthenticatedUser = user;
              _isAuthenticated = true;
              _pageIndex = 0;
              _userRole = _mapUserRoleToString(user.role);
              _currentUserId = user.id;
              
              // IMPORTANT : Mettre à jour le pays et le département selon le rôle
              if (user.role == UserRole.adminPays || user.role == UserRole.adminDepartement) {
                // Utiliser le mapping pour trouver le nom complet du pays
                if (user.countryCode != null && _countryCodeToName.containsKey(user.countryCode)) {
                  _currentUserCountry = _countryCodeToName[user.countryCode]!;
                  print('🔧 LOGIN DEBUG: countryCode=${user.countryCode} => _currentUserCountry=$_currentUserCountry');
                  
                  // Pour Admin Département, trouver aussi le département exact
                  if (user.role == UserRole.adminDepartement && user.departmentCode != null) {
                    final countryData = _usersStructure[_currentUserCountry];
                    if (countryData != null) {
                      for (final deptKey in countryData.keys) {
                        if (deptKey != 'countryAdmin' && deptKey.contains(user.departmentCode!)) {
                          _currentUserDept = deptKey;
                          print('🔧 LOGIN DEBUG: departmentCode=${user.departmentCode} => _currentUserDept=$_currentUserDept');
                          break;
                        }
                      }
                    }
                  }
                } else {
                  print('❌ LOGIN ERROR: countryCode ${user.countryCode} not found in mapping!');
                }
              }
              
              print('✅ LOGIN SUCCESS: Role=$_userRole, Country=$_currentUserCountry, Dept=$_currentUserDept');
            });
            _connectSignalingForCurrentUser();
          },
        ),
      );
    }
    
    // Interface principale après authentification
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: t['title']!,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('fr', 'FR'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: c.bg,
        fontFamily: 'Inter',
      ),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: c.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(_currentAuthenticatedUser?.name ?? ''),
          actions: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getRoleColor(_currentAuthenticatedUser!.role),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _currentAuthenticatedUser!.role.shortLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
          leading: Builder(
            builder: (context) => IconButton(
              icon: Icon(Icons.menu, color: c.textP),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        drawer: Drawer(
          child: SafeArea(
            child: _buildSidebar(),
          ),
        ),
        body: Stack(
          children: [
            Container(
              color: c.bg,
              child: IndexedStack(
                index: _pageIndex,
                children: [
                  _buildHomePage(),
                  _buildDevicesPage(),
                  _buildHistoryPage(),
                  _buildAuthenticationPage(),
                  _buildSettingsPage(),
                  _buildProfilePage(),
                ],
              ),
            ),
            if (_showAddDialog) _buildAddUserDialog(),
            if (_showAddDeptDialog) _buildAddDeptDialog(),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final items = [
      (t['remote_control']!, Icons.desktop_windows_outlined, 0),
      (t['devices']!, Icons.devices_outlined, 1),
      (t['history']!, Icons.history, 2),
      (t['settings']!, Icons.settings_outlined, 4),
      ('Profil', Icons.person_outline, 5),
    ];

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 30, 0, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'BimStreaming',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(top: 4, bottom: 24),
              child: Text(
                t['secure_access']!,
                style: TextStyle(color: c.accent, fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ),
            for (int i = 0; i < items.length; i++) _buildSidebarButton(items[i].$3, items[i].$1, items[i].$2),
            const Spacer(),
            Container(
              margin: const EdgeInsets.all(15),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: _themeMode == ThemeModeType.dark ? 0.03 : 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(100)),
                  ),
                  const SizedBox(width: 10),
                  Text('Alex Chen\nOnline', style: TextStyle(color: c.textP, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarButton(int idx, String text, IconData icon) {
    final active = _pageIndex == idx;
    return InkWell(
      onTap: () {
        setState(() => _pageIndex = idx);
        try {
          Navigator.of(context).pop();
        } catch (e) {
          // Navigator might not be available in drawer context
        }
      },
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
          border: Border(left: BorderSide(color: active ? c.accent : Colors.transparent, width: 3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: active ? c.accent : c.textS),
            const SizedBox(width: 10),
            Text(text, style: TextStyle(color: active ? c.accent : c.textS, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // Helper methods for authentication
  String _mapUserRoleToString(UserRole role) {
    switch (role) {
      case UserRole.adminGlobal:
        return _roleAdminPrincipal;
      case UserRole.adminPays:
        return _roleAdminPays;
      case UserRole.adminDepartement:
        return _roleAdminDepartement;
      case UserRole.client:
        return _roleUser; // Maper client à User pour cohérence
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.adminGlobal:
        return Colors.red[600] ?? Colors.red;
      case UserRole.adminPays:
        return Colors.orange[600] ?? Colors.orange;
      case UserRole.adminDepartement:
        return Colors.blue[600] ?? Colors.blue;
      case UserRole.client:
        return Colors.grey[600] ?? Colors.grey;
    }
  }

  Widget _buildProfilePage() {
    if (_currentAuthenticatedUser == null) {
      return Center(
        child: Text('Erreur: utilisateur non chargé', style: TextStyle(color: c.textP)),
      );
    }

    return UserProfilePage(
      user: _currentAuthenticatedUser!,
      isDarkMode: _themeMode == ThemeModeType.dark,
      translate: (key) => t[key] ?? key,
      onLogout: () {
        _authService.logout();
        _signalSubscription?.cancel();
        _signalingService.disconnect();
        setState(() {
          // Return to login page on logout.
          _initializeGuestUser();
          _isSignalConnected = false;
          _pageIndex = 0;
          _authIdController.clear();
          _authPasswordController.clear();
        });
      },
    );
  }

  Widget _buildHomePage() {
    final hideIdInput = _selectedConnection != 'Recent Connections...';

    return Padding(
      padding: const EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t['remote_control']!, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: c.textP)),
            const SizedBox(height: 6),
            Text(t['remote_sub']!, style: TextStyle(fontSize: 15, color: c.textS)),
            const SizedBox(height: 26),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _glassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t['your_id']!, style: TextStyle(color: c.textS, fontWeight: FontWeight.bold, fontSize: 10)),
                        const SizedBox(height: 10),
                        Text('482 • 991 • 003', style: TextStyle(color: c.accent, fontSize: 34, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 18),
                        Text(t['session_password']!, style: TextStyle(color: c.textS, fontWeight: FontWeight.bold, fontSize: 10)),
                        const SizedBox(height: 8),
                        Text(_sessionPassword, style: TextStyle(color: c.textP, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: 3)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _glassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t['establish']!, style: TextStyle(color: c.textS, fontWeight: FontWeight.bold, fontSize: 10)),
                        const SizedBox(height: 10),
                        _styledDropdown<String>(
                          value: _selectedConnection,
                          items: _recentConnections,
                          onChanged: (v) => setState(() => _selectedConnection = v ?? _recentConnections.first),
                        ),
                        const SizedBox(height: 10),
                        if (!hideIdInput) ...[
                          _styledInput(_idController, t['remote_account_id_hint']!),
                          const SizedBox(height: 10),
                        ],
                        _styledInput(_passwordController, t['session_password_hint']!, obscure: true),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 45,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                            onPressed: _openSupportSession,
                            child: Text(t['connect_btn']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(t['recent_activity']!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.textP)),
            const SizedBox(height: 10),
            _buildSimpleTable(
              headers: const ['Target Device', 'Type', 'Duration', 'Status'],
              rows: const [
                ['Office-Workstation', 'Control', '00:45:12', 'Success'],
                ['Dev-Server-01', 'File Transfer', '00:12:33', 'Success'],
                ['MacBook-Pro-M4', 'Control', '00:03:48', 'Disconnected'],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesPage() {
    final filteredStructure = _getFilteredUsersStructure();

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t['registered_devices']!, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.textP)),
          const SizedBox(height: 12),
          _glassCard(
            child: Column(
              children: [
                TextField(
                  controller: _deviceSearchController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: c.textP),
                  decoration: InputDecoration(
                    hintText: t['search_user_hint']!,
                    hintStyle: TextStyle(color: c.textS),
                    prefixIcon: Icon(Icons.search, color: c.textS),
                    suffixIcon: _deviceSearchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _deviceSearchController.clear();
                              setState(() {});
                            },
                            icon: Icon(Icons.close, color: c.textS),
                          )
                        : null,
                    filled: true,
                    fillColor: c.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _styledDropdown<String>(
                        value: _selectedCountryFilter,
                        items: _countryFilterItems(),
                        labelBuilder: (value) => value == _allFilterValue ? t['filter_all_countries']! : value,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedCountryFilter = value;
                            final departmentItems = _departmentFilterItems();
                            if (!departmentItems.contains(_selectedDepartmentFilter)) {
                              _selectedDepartmentFilter = _allFilterValue;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _styledDropdown<String>(
                        value: _selectedDepartmentFilter,
                        items: _departmentFilterItems(),
                        labelBuilder: (value) => value == _allFilterValue ? t['filter_all_departments']! : value,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedDepartmentFilter = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _styledDropdown<DeviceRoleFilter>(
                        value: _selectedDeviceRoleFilter,
                        items: DeviceRoleFilter.values,
                        labelBuilder: _deviceRoleFilterLabel,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedDeviceRoleFilter = value);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: filteredStructure.isEmpty
                ? Center(
                    child: Text(
                      t['no_users_found']!,
                      style: TextStyle(color: c.textS, fontSize: 14),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...(filteredStructure.entries.map((countryEntry) {
                          return _buildCountrySection(countryEntry.key, countryEntry.value);
                        }).toList()),
                      ],
                    ),
                  ),
          )
        ],
      ),
    );
  }

  Widget _buildCountrySection(String countryName, Map<String, dynamic> countryData) {
    final countryAdmin = countryData['countryAdmin'] as Map<String, String>?;
    final isCollapsed = _isCountryCollapsed(countryName);
    
    // Vérifier les permissions pour créer un département
    final canCreateDept = _userRole == _roleAdminPrincipal || 
                          (_userRole == _roleAdminPays && _currentUserCountry == countryName);
    
    print('🏳️ COUNTRY SECTION: $countryName');
    print('   _userRole=$_userRole, _currentUserCountry=$_currentUserCountry');
    print('   canCreateDept=$canCreateDept (condition: $_userRole == $_roleAdminPays && $_currentUserCountry == $countryName)');
    
    // Filtrer les départements (exclure countryAdmin)
    final departments = Map<String, dynamic>.from(countryData)..remove('countryAdmin');
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(countryName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.accent)),
              const Spacer(),
              if (canCreateDept)
                SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => _openAddDeptDialog(countryName),
                    child: Text(t['btn_create_department']!, style: const TextStyle(fontSize: 11)),
                  ),
                ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _toggleCountryCollapse(countryName),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isCollapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    size: 18,
                    color: c.accent,
                  ),
                ),
              ),
            ],
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 16),
            if (countryAdmin != null) _buildCountryAdminCard(countryAdmin),
            ...departments.entries.map((deptEntry) {
              return _buildDepartmentSection(
                deptEntry.key,
                Map<String, String>.from(deptEntry.value['admin']),
                List<Map<String, String>>.from((deptEntry.value['users'] as List).map((u) => Map<String, String>.from(u))),
                countryName,
                showAdmin: deptEntry.value['showAdmin'] ?? true,
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildDepartmentSection(
    String deptName,
    Map<String, String> deptAdmin,
    List<Map<String, String>> users,
    String country, {
    bool showAdmin = true,
  }) {
    final isCollapsed = _isDepartmentCollapsed(country, deptName);
    
    // Vérifier les permissions
    final canManage = _userRole == _roleAdminPrincipal || 
                      (_userRole == _roleAdminPays && _currentUserCountry == country) ||
                      (_userRole == _roleAdminDepartement && _currentUserDept == deptName && _currentUserCountry == country);
    
    final canDeleteDept = _userRole == _roleAdminPrincipal || 
                          (_userRole == _roleAdminPays && _currentUserCountry == country);
    
    print('📁 DEPT SECTION: $deptName in $country');
    print('   _userRole=$_userRole, _currentUserCountry=$_currentUserCountry, _currentUserDept=$_currentUserDept');
    print('   canManage=$canManage, canDeleteDept=$canDeleteDept');

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('📁 $deptName', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textP)),
              const Spacer(),
              if (canManage)
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () => _showAddUserDialog(country, deptName),
                    child: Text(t['btn_add']!, style: const TextStyle(fontSize: 10)),
                  ),
                ),
              if (canDeleteDept) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _deleteDepartment(country, deptName),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: c.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.delete_outline, size: 18, color: c.danger),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _toggleDepartmentCollapse(country, deptName),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isCollapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    size: 18,
                    color: c.accent,
                  ),
                ),
              ),
            ],
          ),
          if (!isCollapsed) ...[
            if (showAdmin) ...[
              const SizedBox(height: 10),
              _buildAdminCard(deptAdmin, canManage, country, deptName),
              const SizedBox(height: 10),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: users.map((user) => _buildUserCard(user, canManage, country, deptName)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdminCard(Map<String, String> admin, bool canManage, String country, String department) {
    final name = admin['name'] ?? '';
    final id = admin['id'] ?? '';
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _handleDeviceUserTap(admin),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.accent, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(50)),
                child: const Center(child: Text('👨', style: TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: c.textP, fontSize: 12)),
                    Text('ID: $id', style: TextStyle(color: c.textS, fontSize: 9)),
                    Text('Admin', style: TextStyle(color: c.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(4)),
                child: const Text('Admin', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, String> user, bool canManage, String country, String department) {
    final name = user['name'] ?? '';
    final id = user['id'] ?? '';
    final userType = user['role'] ?? _userTypeStandard;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _handleDeviceUserTap(user),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              const Text('👤', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontWeight: FontWeight.w500, color: c.textP, fontSize: 11)),
                    Text('ID: $id', style: TextStyle(color: c.textS, fontSize: 9)),
                    Text(_userTypeLabel(userType), style: TextStyle(color: c.textS, fontSize: 9)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: c.success.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3)),
                child: Text('Online', style: TextStyle(color: c.success, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
              if (canManage) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: InkWell(
                    onTap: () => _promoteToAdmin(country, department, user),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.arrow_upward, size: 14, color: c.accent),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: InkWell(
                    onTap: () => _deleteUser(country, department, id),
                    child: Icon(Icons.close, size: 16, color: c.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountryAdminCard(Map<String, String> admin) {
    final name = admin['name'] ?? '';
    final id = admin['id'] ?? '';
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _handleDeviceUserTap(admin),
        child: Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.accent.withValues(alpha: 0.2), c.accent.withValues(alpha: 0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.accent, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [c.accent, c.accent.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(50)),
                child: const Center(child: Text('👑', style: TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: c.textP, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('ID: $id', style: TextStyle(color: c.textS, fontSize: 10)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(3)),
                          child: const Text('Admin Pays', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.success.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('Online', style: TextStyle(color: c.success, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.star, color: Colors.amber, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryPage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t['connection_history']!, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.textP)),
          const SizedBox(height: 20),
          Expanded(
            child: _buildSimpleTable(
              headers: const ['Date', 'Node ID', 'Duration', 'Status'],
              rows: List.generate(10, (i) => ['2026-02-${(i + 10)}', '482-991-${100 + i}', '00:${(i + 2).toString().padLeft(2, '0')}:12', i.isEven ? 'Success' : 'Timeout']),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthenticationPage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t['authentication']!, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.textP)),
          const SizedBox(height: 8),
          Text(
            '${t['current_role']!}: ${_appRoleLabel(_userRole)}',
            style: TextStyle(color: c.textS, fontSize: 13),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 520,
            child: _glassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _styledInput(_authIdController, t['id_field_hint']!),
                  const SizedBox(height: 12),
                  _styledInput(_authPasswordController, t['password_field_hint']!, obscure: true),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: Text(t['forgot_password']!, style: TextStyle(color: c.accent)),
                    ),
                  ),
                  if (_recoveryMaskedEmail.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${t['recovery_sent_to']!} $_recoveryMaskedEmail', style: TextStyle(color: c.textP, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(t['recovery_message_sent']!, style: TextStyle(color: c.textS, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text('${t['recovery_test_code']!} $_recoveryTestCode', style: TextStyle(color: c.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _styledInput(_recoveryCodeController, t['recovery_code_hint']!),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                        onPressed: _verifyRecoveryCode,
                        child: Text(t['recovery_verify_code_btn']!),
                      ),
                    ),
                  ],
                  if (_recoveryCodeVerified) ...[
                    const SizedBox(height: 10),
                    _styledInput(_newPasswordController, t['recovery_new_password_hint']!, obscure: true),
                    const SizedBox(height: 8),
                    _styledInput(_confirmPasswordController, t['recovery_confirm_password_hint']!, obscure: true),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: c.success, foregroundColor: Colors.white),
                        onPressed: _submitPasswordReset,
                        child: Text(t['recovery_reset_password_btn']!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                      onPressed: _authenticateWithAuthService,
                      child: Text(t['authenticate_btn']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () {
                      setState(() => _showDemoUsers = !_showDemoUsers);
                    },
                    child: Row(
                      children: [
                        Icon(
                          _showDemoUsers ? Icons.expand_less : Icons.expand_more,
                          color: c.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Utilisateurs Démo',
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showDemoUsers) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 320,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDemoUserRow('Admin Principal', 'admin1', 'admin123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Admin France', 'admin_fr', 'france123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Admin IT France', 'admin_de_fr', 'it_france123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Admin USA', 'admin_us', 'usa123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Admin HR USA', 'admin_de_us', 'hr_usa123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Admin Pays (France)', 'CADM001', 'countryadmin'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Admin IT France', 'ADM001', 'admin123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('User (France IT)', 'USR001', 'pass123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Technicien (France IT)', 'USR003', 'pass123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('User (France HR)', 'USR004', 'pass123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Admin USA Pays', 'CADM002', 'countryadmin'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('Admin Finance USA', 'ADM003', 'admin123'),
                              const SizedBox(height: 10),
                              _buildDemoUserRow('User (USA Finance)', 'USR006', 'pass123'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoUserRow(String role, String id, String password) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            role,
            style: TextStyle(
              color: c.textP,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _authIdController.text = id;
                  },
                  child: Row(
                    children: [
                      Text(
                        'ID: ',
                        style: TextStyle(color: c.textS, fontSize: 10),
                      ),
                      Expanded(
                        child: Text(
                          id,
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Courier',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _authPasswordController.text = password;
                  },
                  child: Row(
                    children: [
                      Text(
                        'MDP: ',
                        style: TextStyle(color: c.textS, fontSize: 10),
                      ),
                      Expanded(
                        child: Text(
                          password,
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Courier',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t['platform_settings']!, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.textP)),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: _glassCard(
                child: Column(
                  children: [
                    _settingsRow(
                      'Interface Theme:',
                      _styledDropdown<ThemeModeType>(
                        value: _themeMode,
                        items: ThemeModeType.values,
                        labelBuilder: (v) => v == ThemeModeType.dark ? 'Dark Mode' : 'Light Mode',
                        onChanged: (v) {
                          if (v != null) {
                            _setThemeMode(v);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    _settingsRow(
                      t['language']!,
                      _styledDropdown<Lang>(
                        value: _lang,
                        items: Lang.values,
                        labelBuilder: (v) => v == Lang.en ? 'English' : 'Français',
                        onChanged: (v) {
                          if (v != null) {
                            _setLanguage(v);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    _settingsToggleRow(t['end_to_end']!),
                    const SizedBox(height: 12),
                    _settingsToggleRow(t['autostart']!),
                    const SizedBox(height: 12),
                    _settingsToggleRow(t['hardware']!),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSupportPage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              _iconButton(Icons.arrow_back, () => setState(() => _pageIndex = 0)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BIM Remote Support', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: c.textP)),
                  Text('Internal Secure Network', style: TextStyle(fontSize: 11, color: c.accent)),
                ],
              ),
              const Spacer(),
              Text('● Connected    Session: 00:00:52    🔒 AES-256 Encrypted', style: TextStyle(color: c.textS, fontSize: 11)),
              const SizedBox(width: 14),
              SizedBox(
                height: 35,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white),
                  onPressed: () => setState(() => _pageIndex = 0),
                  child: Text(t['btn_disconnect']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: _isSupportVideoExpanded ? 1 : 5,
                  child: _buildSupportVideoPanel(),
                ),
                if (!_isSupportVideoExpanded) ...[
                  const SizedBox(width: 14),
                  SizedBox(width: 340, child: _buildSupportSidePanel()),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 80,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: c.border),
            ),
            child: Text(
              '[14:38:45] Connection established    [14:38:46] Session key negotiated: AES-256',
              style: TextStyle(fontSize: 10, color: c.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportVideoPanel() {
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              '⌛ Waiting for connection...\nConnect to a remote machine to start session',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textS, fontSize: 14),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _iconButton(
              _isSupportVideoExpanded ? Icons.close_fullscreen : Icons.open_in_full,
              _toggleSupportFullscreen,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSupportFullscreen() async {
    final nextExpanded = !_isSupportVideoExpanded;
    setState(() => _isSupportVideoExpanded = nextExpanded);

    if (!kIsWeb && io.Platform.isWindows) {
      await windowManager.setFullScreen(nextExpanded);
    }
  }

  Widget _buildSupportSidePanel() {
    return Container(
      decoration: BoxDecoration(
        color: c.sidebar,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _supportTabButton(SupportTab.chat, '💬 ${t['tab_chat']!}'),
                const SizedBox(width: 6),
                _supportTabButton(SupportTab.transfer, '📁 ${t['tab_transfer']!}'),
                const SizedBox(width: 6),
                _supportTabButton(SupportTab.command, '⌨ ${t['tab_command']!}'),
              ],
            ),
          ),
          Expanded(child: _buildSupportTabContent()),
        ],
      ),
    );
  }

  Widget _buildSupportTabContent() {
    switch (_supportTab) {
      case SupportTab.chat:
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: ListView.builder(
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, i) => Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(8)),
                        child: Text(_chatMessages[i], style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _styledInput(_chatController, 'Message...')),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white, padding: EdgeInsets.zero),
                      onPressed: _sendMessage,
                      child: const Text('➤'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case SupportTab.transfer:
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                    onPressed: _uploadFile,
                    child: Text(t['btn_upload_file']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                    onPressed: () => _showStubMessage('Download File (stub Flutter)'),
                    child: Text(t['btn_download_file']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      case SupportTab.command:
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(_commandOutput, style: TextStyle(color: c.textS)),
                ),
              ),
              const SizedBox(height: 8),
              _styledInput(_commandController, 'Enter command...'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                  onPressed: _executeCommand,
                  child: Text(t['btn_execute']!),
                ),
              )
            ],
          ),
        );
    }
  }

  Widget _supportTabButton(SupportTab tab, String label) {
    final active = _supportTab == tab;
    return Expanded(
      child: SizedBox(
        height: 34,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: active ? c.accent.withValues(alpha: 0.18) : c.card,
            foregroundColor: active ? c.accent : c.textP,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () => setState(() => _supportTab = tab),
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Icon(icon, size: 18, color: c.textP),
      ),
    );
  }

  Widget _statCard(String title, String value, Color valueColor) {
    return Container(
      width: 140,
      height: 80,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 10, color: c.textS)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
        boxShadow: const [BoxShadow(color: Color.fromARGB(50, 0, 0, 0), blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: child,
    );
  }

  Widget _buildSimpleTable({required List<String> headers, required List<List<String>> rows}) {
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: TextStyle(color: c.textP, fontWeight: FontWeight.bold),
          dataTextStyle: TextStyle(color: c.textP),
          columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
          rows: rows.map((r) => DataRow(cells: r.map((cell) => DataCell(Text(cell))).toList())).toList(),
        ),
      ),
    );
  }

  Widget _styledInput(TextEditingController controller, String hint, {bool obscure = false}) {
    return SizedBox(
      height: 45,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(color: c.textP),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.textS),
          filled: true,
          fillColor: c.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.accent)),
        ),
      ),
    );
  }

  Widget _settingsRow(String label, Widget action) {
    return Row(
      children: [
        Text(label, style: TextStyle(color: c.textP, fontSize: 14)),
        const Spacer(),
        SizedBox(width: 170, child: action),
      ],
    );
  }

  Widget _settingsToggleRow(String label) {
    return Row(
      children: [
        Text(label, style: TextStyle(color: c.textP, fontSize: 14)),
        const Spacer(),
        Container(
          width: 64,
          height: 32,
          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(15)),
          child: const Center(
            child: Text('ON', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        )
      ],
    );
  }

  Widget _styledDropdown<T>({
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    String Function(T)? labelBuilder,
  }) {
    return Container(
      height: 45,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: c.card,
        style: TextStyle(color: c.textP),
        items: items
            .map(
              (v) => DropdownMenuItem<T>(
                value: v,
                child: Text(labelBuilder != null ? labelBuilder(v) : '$v'),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

enum ThemeModeType { dark, light }

enum Lang { en, fr }

enum DeviceRoleFilter { all, countryAdmin, departmentAdmin, user, technician }

enum SupportTab { chat, transfer, command }

class AppColors {
  final Color bg;
  final Color sidebar;
  final Color card;
  final Color accent;
  final Color success;
  final Color danger;
  final Color textP;
  final Color textS;
  final Color border;

  const AppColors({
    required this.bg,
    required this.sidebar,
    required this.card,
    required this.accent,
    required this.success,
    required this.danger,
    required this.textP,
    required this.textS,
    required this.border,
  });

  static const dark = AppColors(
    bg: Color(0xFF121417),
    sidebar: Color(0xFF181C21),
    card: Color(0xFF1E2228),
    accent: Color(0xFF5B8DEF),
    success: Color(0xFF2ECC71),
    danger: Color(0xFFE74C3C),
    textP: Color(0xFFEAECEF),
    textS: Color(0xFF9AA4B2),
    border: Color(0xFF2D343D),
  );

  static const light = AppColors(
    bg: Color(0xFFF0F2F5),
    sidebar: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF0066FF),
    success: Color(0xFF28A745),
    danger: Color(0xFFDC3545),
    textP: Color(0xFF1C1E21),
    textS: Color(0xFF606770),
    border: Color(0xFFDADDE1),
  );
}

const Map<Lang, Map<String, String>> _translations = {
  Lang.en: {
    'title': 'BimStreaming Remote Desktop',
    'platform_settings': 'Platform Settings',
    'end_to_end': 'End-to-End Encryption',
    'autostart': 'Auto-start on Boot',
    'hardware': 'Hardware Acceleration',
    'language': 'Language:',
    'remote_control': 'Remote Control',
    'remote_sub': 'Manage peer-to-peer encrypted sessions.',
    'your_id': 'YOUR DEVICE ID',
    'session_password': 'SESSION PASSWORD',
    'establish': 'ESTABLISH CONNECTION',
    'recent_activity': 'Recent Activity',
    'connect_btn': 'Connect to Device',
    'remote_account_id_hint': 'Enter target account ID...',
    'session_password_hint': 'Enter session password...',
    'remote_account_required': 'Please enter the target account ID.',
    'session_created_with_code': 'Session created. Code: {code}',
    'registered_devices': 'Registered Devices',
    'connection_history': 'Connection History',
    'secure_access': 'SECURE ACCESS',
    'devices': 'Devices',
    'history': 'History',
    'authentication': 'Authentication',
    'settings': 'Settings',
    'btn_cancel': 'Cancel',
    'btn_add': 'Add',
    'btn_create': 'Create',
    'btn_create_department': '+ Create Department',
    'btn_disconnect': 'Disconnect',
    'btn_upload_file': 'Upload File',
    'btn_download_file': 'Download File',
    'btn_execute': 'Execute',
    'tab_chat': 'Chat',
    'tab_transfer': 'Transfer',
    'tab_command': 'Command',
    'authenticate_btn': 'Authenticate',
    'forgot_password': 'Forgot password?',
    'forgot_password_message': 'Please contact your administrator to reset your password.',
    'recovery_enter_id_first': 'Enter your ID first.',
    'recovery_sent_to': 'Recovery email:',
    'recovery_message_sent': 'A recovery message has been sent to this email.',
    'recovery_test_code': 'Test code:',
    'recovery_code_hint': 'Enter verification code',
    'recovery_verify_code_btn': 'Verify code',
    'recovery_invalid_code': 'Invalid verification code.',
    'recovery_code_valid': 'Code verified successfully.',
    'recovery_new_password_hint': 'Enter new password',
    'recovery_confirm_password_hint': 'Confirm new password',
    'recovery_reset_password_btn': 'Update password',
    'recovery_fill_passwords': 'Please fill both password fields.',
    'recovery_password_mismatch': 'Passwords do not match.',
    'recovery_password_updated': 'Password updated successfully.',
    'auth_fill_all_fields': 'Please fill ID and password.',
    'auth_invalid_credentials': 'Invalid credentials.',
    'auth_success': 'Authentication successful.',
    'current_role': 'Current role',
    'profile_id_label': 'ID',
    'profile_permissions': 'Permissions',
    'profile_permission_view_title': 'View devices',
    'profile_permission_modify_title': 'Modify devices',
    'profile_permission_add_title': 'Add devices',
    'profile_permission_delete_title': 'Delete devices',
    'profile_region_info': 'Zone Information',
    'profile_country_label': 'Country',
    'profile_department_label': 'Department',
    'logout_confirm_title': 'Confirmation',
    'logout_confirm_message': 'Are you sure you want to disconnect?',
    'profile_view_all_devices': 'View all devices',
    'profile_view_country_devices': 'View devices in',
    'profile_view_department_devices': 'View devices in department',
    'profile_modify_all_devices': 'Modify all devices',
    'profile_modify_country_devices': 'Modify devices in',
    'profile_modify_department_devices': 'Modify devices in department',
    'profile_add_all_devices': 'Add devices globally',
    'profile_add_country_devices': 'Add devices in',
    'profile_add_department_devices': 'Add devices in department',
    'profile_delete_all_devices': 'Delete all devices',
    'profile_delete_country_devices': 'Delete devices in',
    'profile_delete_department_devices': 'Delete devices in department',
    'profile_no_access': 'No access',
    'id_field_hint': 'Enter your ID',
    'password_field_hint': 'Enter your password',
    'role_admin_principal': 'Principal Admin',
    'add_user_title': 'Add User',
    'password': 'Password',
    'password_hint': 'Enter password',
    'name': 'Name',
    'full_name_hint': 'Full user name',
    'search_user_hint': 'Search by name, ID, country or department...',
    'filter_all_countries': 'All Countries',
    'filter_all_departments': 'All Departments',
    'filter_all_roles': 'All Roles',
    'role_country_admin': 'Country Admin',
    'role_department_admin': 'Department Admin',
    'role_user': 'User',
    'role_it_technician': 'IT Technician',
    'user_role_field': 'User Role',
    'no_users_found': 'No users match the current filters.',
    'device_pick_another_user': 'Please select another user to connect.',
    'connection_request_title': 'Connection request',
    'waiting_other_user_accept': 'Waiting for {name} to accept.',
    'connecting_to_user': 'Connecting to {name}...',
    'connection_request_sent': 'Connection request sent to {name}.',
    'incoming_connection_request': '{name} wants to connect to your session.',
    'btn_accept': 'Accept',
    'btn_reject': 'Reject',
    'connection_accepted': '{name} accepted your request.',
    'connection_rejected': 'Connection request rejected.',
    'connection_rejected_by': '{name} rejected your request.',
    'signaling_offline': 'Signaling server unavailable. Start backend first.',
    'request_failed': 'Request failed.',
    'btn_ok': 'OK',
    'remote_support_title': 'BIM Remote Support',
    'internal_secure_network': 'Internal Secure Network',
    'status_connected': 'Connected',
    'status_disconnected': 'Disconnected',
    'session_label': 'Session',
    'full_screen_mode': 'Full screen session mode',
    'remote_session_active': 'Remote session is active',
    'full_screen': 'Full Screen',
    'exit_full_screen': 'Exit Full Screen',
    'chat_message_hint': 'Message...',
    'command_hint': 'Write your command...',
    'command_executed_success': 'Command executed successfully',
    'upload_canceled': 'Upload canceled.',
    'selected_for_upload': 'Selected for upload',
    'save_downloaded_file': 'Save downloaded file',
    'download_canceled': 'Download canceled.',
    'download_target_selected': 'Download target selected',
    'save_screenshot_file': 'Save screenshot',
    'screenshot_save_canceled': 'Screenshot save canceled.',
    'screenshot_saved_to': 'Screenshot saved to',
    'screenshot_failed': 'Screenshot failed',
    'btn_screenshot': 'Screenshot',
    'btn_record': 'Record',
    'btn_stop_record': 'Stop',
    'btn_audio': 'Audio',
    'btn_lock': 'Lock',
    'btn_reboot': 'Reboot',
    'btn_privacy': 'Privacy',
    'screenshot_taken': 'Screenshot captured',
    'recording_started': 'Recording session...',
    'recording_stopped': 'Recording stopped',
    'audio_enabled': 'Audio enabled',
    'audio_disabled': 'Audio disabled',
    'device_locked': 'Device locked',
    'confirm_reboot': 'Confirm Reboot',
    'reboot_warning': 'Do you really want to reboot the device?',
    'device_rebooting': 'Device rebooting...',
    'privacy_mode_active': 'Privacy Mode Active',
    'screen_is_hidden': 'Your screen is hidden from this session',
    'privacy_mode_enabled': 'Privacy mode enabled - screen hidden',
    'privacy_mode_disabled': 'Privacy mode disabled - screen visible',
  },
  Lang.fr: {
    'title': 'BimStreaming Bureau à distance',
    'platform_settings': 'Paramètres de la plateforme',
    'end_to_end': 'Chiffrement de bout en bout',
    'autostart': 'Démarrage automatique',
    'hardware': 'Accélération matérielle',
    'language': 'Langue :',
    'remote_control': 'Contrôle à distance',
    'remote_sub': 'Gérer les sessions chiffrées pair à pair.',
    'your_id': 'VOTRE ID APPAREIL',
    'session_password': 'MOT DE PASSE SESSION',
    'establish': 'ÉTABLIR LA CONNEXION',
    'recent_activity': 'Activité récente',
    'connect_btn': 'Se connecter à un appareil',
    'remote_account_id_hint': 'Entrez l\'ID du compte cible...',
    'session_password_hint': 'Entrez le mot de passe de session...',
    'remote_account_required': 'Veuillez entrer l\'ID du compte cible.',
    'session_created_with_code': 'Session créée. Code : {code}',
    'registered_devices': 'Appareils enregistrés',
    'connection_history': 'Historique des connexions',
    'secure_access': 'ACCÈS SÉCURISÉ',
    'devices': 'Appareils',
    'history': 'Historique',
    'settings': 'Paramètres',
    'authentication': 'Authentification',
    'btn_cancel': 'Annuler',
    'btn_add': 'Ajouter',
    'btn_create': 'Créer',
    'btn_create_department': '+ Créer Département',
    'btn_disconnect': 'Déconnecter',
    'btn_upload_file': 'Téléverser un fichier',
    'btn_download_file': 'Télécharger un fichier',
    'btn_execute': 'Exécuter',
    'tab_chat': 'Chat',
    'tab_transfer': 'Transfert',
    'tab_command': 'Commande',
    'authenticate_btn': 'S’authentifier',
    'forgot_password': 'Mot de passe oublié ?',
    'forgot_password_message': 'Veuillez contacter votre administrateur pour réinitialiser le mot de passe.',
    'recovery_enter_id_first': 'Entrez votre ID d’abord.',
    'recovery_sent_to': 'Email de récupération :',
    'recovery_message_sent': 'Un message de récupération a été envoyé à cet email.',
    'recovery_test_code': 'Code de test :',
    'recovery_code_hint': 'Entrez le code de vérification',
    'recovery_verify_code_btn': 'Vérifier le code',
    'recovery_invalid_code': 'Code de vérification invalide.',
    'recovery_code_valid': 'Code vérifié avec succès.',
    'recovery_new_password_hint': 'Entrez le nouveau mot de passe',
    'recovery_confirm_password_hint': 'Confirmez le nouveau mot de passe',
    'recovery_reset_password_btn': 'Mettre à jour le mot de passe',
    'recovery_fill_passwords': 'Veuillez remplir les deux champs mot de passe.',
    'recovery_password_mismatch': 'Les mots de passe ne correspondent pas.',
    'recovery_password_updated': 'Mot de passe mis à jour avec succès.',
    'auth_fill_all_fields': 'Veuillez remplir ID et mot de passe.',
    'auth_invalid_credentials': 'Identifiants invalides.',
    'auth_success': 'Authentification réussie.',
    'current_role': 'Rôle actuel',
    'profile_id_label': 'ID',
    'profile_permissions': 'Permissions',
    'profile_permission_view_title': 'Voir les appareils',
    'profile_permission_modify_title': 'Modifier les appareils',
    'profile_permission_add_title': 'Ajouter des appareils',
    'profile_permission_delete_title': 'Supprimer des appareils',
    'profile_region_info': 'Informations de zone',
    'profile_country_label': 'Pays',
    'profile_department_label': 'Département',
    'logout_confirm_title': 'Confirmation',
    'logout_confirm_message': 'Êtes-vous sûr de vouloir vous déconnecter ?',
    'profile_view_all_devices': 'Voir tous les appareils',
    'profile_view_country_devices': 'Voir les appareils du pays',
    'profile_view_department_devices': 'Voir les appareils du département',
    'profile_modify_all_devices': 'Modifier tous les appareils',
    'profile_modify_country_devices': 'Modifier les appareils du pays',
    'profile_modify_department_devices': 'Modifier les appareils du département',
    'profile_add_all_devices': 'Ajouter des appareils globaux',
    'profile_add_country_devices': 'Ajouter des appareils au pays',
    'profile_add_department_devices': 'Ajouter des appareils au département',
    'profile_delete_all_devices': 'Supprimer tous les appareils',
    'profile_delete_country_devices': 'Supprimer les appareils du pays',
    'profile_delete_department_devices': 'Supprimer les appareils du département',
    'profile_no_access': 'Aucun accès',
    'id_field_hint': 'Entrez votre ID',
    'password_field_hint': 'Entrez votre mot de passe',
    'role_admin_principal': 'Admin Principal',
    'add_user_title': 'Ajouter un utilisateur',
    'password': 'Mot de passe',
    'password_hint': 'Entrez le mot de passe',
    'name': 'Nom',
    'full_name_hint': 'Nom complet de l\'utilisateur',
    'search_user_hint': 'Rechercher par nom, ID, pays ou département...',
    'filter_all_countries': 'Tous les pays',
    'filter_all_departments': 'Tous les départements',
    'filter_all_roles': 'Tous les rôles',
    'role_country_admin': 'Admin Pays',
    'role_department_admin': 'Admin Département',
    'role_user': 'Utilisateur',
    'role_it_technician': 'Technicien Informatique',
    'user_role_field': 'Rôle utilisateur',
    'no_users_found': 'Aucun utilisateur ne correspond aux filtres.',
    'device_pick_another_user': 'Veuillez sélectionner un autre utilisateur pour vous connecter.',
    'connection_request_title': 'Demande de connexion',
    'waiting_other_user_accept': 'En attente de l\'acceptation de {name}.',
    'connecting_to_user': 'Connexion à {name}...',
    'connection_request_sent': 'Demande de connexion envoyée à {name}.',
    'incoming_connection_request': '{name} veut se connecter à votre session.',
    'btn_accept': 'Accepter',
    'btn_reject': 'Refuser',
    'connection_accepted': '{name} a accepté votre demande.',
    'connection_rejected': 'Demande de connexion refusée.',
    'connection_rejected_by': '{name} a refusé votre demande.',
    'signaling_offline': 'Serveur signaling indisponible. Lancez le backend.',
    'request_failed': 'Échec de la requête.',
    'btn_ok': 'OK',
    'remote_support_title': 'Support à distance BIM',
    'internal_secure_network': 'Réseau interne sécurisé',
    'status_connected': 'Connecté',
    'status_disconnected': 'Déconnecté',
    'session_label': 'Session',
    'full_screen_mode': 'Mode session plein écran',
    'remote_session_active': 'Session distante active',
    'full_screen': 'Plein écran',
    'exit_full_screen': 'Quitter le plein écran',
    'chat_message_hint': 'Message...',
    'command_hint': 'Écrivez votre commande...',
    'command_executed_success': 'Commande exécutée avec succès',
    'upload_canceled': 'Téléversement annulé.',
    'selected_for_upload': 'Sélectionné pour téléversement',
    'save_downloaded_file': 'Enregistrer le fichier téléchargé',
    'download_canceled': 'Téléchargement annulé.',
    'download_target_selected': 'Destination de téléchargement sélectionnée',
    'save_screenshot_file': 'Enregistrer la capture',
    'screenshot_save_canceled': 'Enregistrement de la capture annulé.',
    'screenshot_saved_to': 'Capture enregistrée dans',
    'screenshot_failed': 'Échec de la capture',
    'btn_screenshot': 'Capture',
    'btn_record': 'Enregistrer',
    'btn_stop_record': 'Arrêter',
    'btn_audio': 'Audio',
    'btn_lock': 'Verrouiller',
    'btn_reboot': 'Redémarrer',
    'btn_privacy': 'Confidentialité',
    'screenshot_taken': 'Capture d\'écran effectuée',
    'recording_started': 'Enregistrement en cours...',
    'recording_stopped': 'Enregistrement arrêté',
    'audio_enabled': 'Audio activé',
    'audio_disabled': 'Audio désactivé',
    'device_locked': 'Appareil verrouillé',
    'confirm_reboot': 'Confirmer le redémarrage',
    'reboot_warning': 'Voulez-vous vraiment redémarrer l\'appareil ?',
    'device_rebooting': 'Appareil en cours de redémarrage...',
    'privacy_mode_active': 'Mode Privé Actif',
    'screen_is_hidden': 'Votre écran est masqué de cette session',
    'privacy_mode_enabled': 'Mode privé activé - écran masqué',
    'privacy_mode_disabled': 'Mode privé désactivé - écran visible',
  },
};
