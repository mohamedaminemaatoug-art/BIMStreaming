import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_strings.dart';
import '../state/appearance_controller.dart';
import '../state/auth_controller.dart';
import '../state/data_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _inviteUserIdController = TextEditingController();
  final TextEditingController _inviteSessionPasswordController =
      TextEditingController();

  bool _loading = false;
  bool _inviting = false;
  String? _error;
  String? _deviceId;
  String? _sessionPassword;
  bool _isOnline = false;
  List<Map<String, dynamic>> _history = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _inviteUserIdController.dispose();
    _inviteSessionPasswordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final me = await api.get('/users/me');
      final history = await api.get('/remote/history');
      final user = Map<String, dynamic>.from((me['user'] as Map?) ?? const {});
      final deviceSession = Map<String, dynamic>.from(
        (me['device_session'] as Map?) ?? const {},
      );
      final rows = ((history['data'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from((e as Map?) ?? const {}))
          .toList();

      if (!mounted) {
        return;
      }
      setState(() {
        _deviceId = (user['device_id'] ?? deviceSession['device_id'] ?? '-')
            .toString();
        _sessionPassword =
            (deviceSession['session_password'] ??
                    deviceSession['password'] ??
                    '-')
                .toString();
        _isOnline =
          ((user['is_online'] as bool?) ?? false) ||
          ref.read(authControllerProvider).isAuthenticated;
        _history = rows;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load home data. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyDeviceId() async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty || deviceId == '-') {
      return;
    }
    await Clipboard.setData(ClipboardData(text: deviceId));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(ref.read(localeProvider)).deviceIdCopied)),
    );
  }

  Future<void> _sendInvite() async {
    final userId = _inviteUserIdController.text.trim();
    final sessionPassword = _inviteSessionPasswordController.text.trim();
    if (userId.isEmpty || sessionPassword.isEmpty) {
      return;
    }
    setState(() {
      _inviting = true;
    });
    try {
      await ref.read(apiClientProvider).post(
        '/remote/invite/$userId',
        body: {'session_password': sessionPassword},
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(AppStrings.of(ref.read(localeProvider)).connectionInviteSent)),
      );
      _inviteUserIdController.clear();
      _inviteSessionPasswordController.clear();
    } catch (e) {
      if (!mounted) {
        return;
      }
      final message = e.toString().trim().isEmpty
          ? 'Invite failed. Please try again.'
          : 'Invite failed: ${e.toString()}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _inviting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final strings = AppStrings.of(ref.watch(localeProvider));
    ref.listen<AsyncValue<WSMessage>>(wsProvider, (previous, next) {
      next.whenData((message) {
        if (message.type != 'user:online' && message.type != 'user:offline') {
          return;
        }

        final eventUserId = (message.data['user_id'] ?? '').toString();
        final currentUserId = auth.user?.id ?? '';
        if (eventUserId.isEmpty || eventUserId != currentUserId || !mounted) {
          return;
        }

        setState(() {
          _isOnline = message.type == 'user:online';
        });
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.home),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? const Center(child: Text('Unable to load home data right now.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.deviceId,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      _deviceId ?? '-',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _copyDeviceId,
                                    icon: const Icon(Icons.copy),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                strings.sessionPassword,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(_sessionPassword ?? '-'),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _isOnline
                                          ? Colors.green
                                          : Colors.grey,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_isOnline ? 'Online' : 'Offline'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.establishConnection,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _inviteUserIdController,
                                decoration: InputDecoration(
                                  labelText: strings.targetDeviceId,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _inviteSessionPasswordController,
                                decoration: InputDecoration(
                                  labelText: strings.targetSessionPassword,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _inviting ? null : _sendInvite,
                                  icon: const Icon(Icons.link),
                                  label: Text(
                                    _inviting ? 'Sending...' : 'Send Invite',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent Activity',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        if (_history.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('No remote activity yet.'),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Target User')),
                                DataColumn(label: Text('Device ID')),
                                DataColumn(label: Text('Type')),
                                DataColumn(label: Text('Duration')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Started')),
                              ],
                              rows: _history.map((entry) {
                                final startedAt = DateTime.tryParse(
                                  (entry['started_at'] ?? '').toString(),
                                );
                                final startedText = startedAt == null
                                    ? '-'
                                    : '${startedAt.year}-${startedAt.month.toString().padLeft(2, '0')}-${startedAt.day.toString().padLeft(2, '0')} ${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        (entry['target_username'] ?? '-')
                                            .toString(),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        (entry['target_device_id'] ?? '-')
                                            .toString(),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        (entry['session_type'] ?? '-')
                                            .toString(),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        (entry['duration_hms'] ?? '-')
                                            .toString(),
                                      ),
                                    ),
                                    DataCell(
                                      Text((entry['status'] ?? '-').toString()),
                                    ),
                                    DataCell(Text(startedText)),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
