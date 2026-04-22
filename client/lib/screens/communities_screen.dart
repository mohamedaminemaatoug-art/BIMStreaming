import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/state/auth_controller.dart';
import '../../app/state/data_providers.dart';

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  @override
  void initState() {
    super.initState();
    // Load communities on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(communitiesControllerProvider.notifier).loadCommunities();
    });
  }

  @override
  Widget build(BuildContext context) {
    final communitiesState = ref.watch(communitiesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Communities'),
        actions: [
          IconButton(
            icon: const Icon(Icons.login),
            tooltip: 'Join Community',
            onPressed: () => _showJoinByCodeDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(communitiesControllerProvider.notifier)
                .loadCommunities(),
          ),
        ],
      ),
      body: communitiesState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : communitiesState.error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Unable to load communities right now.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(communitiesControllerProvider.notifier)
                        .loadCommunities(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : communitiesState.communities.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.groups_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text('No communities available'),
                ],
              ),
            )
          : CommunitiesList(communities: communitiesState.communities),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateCommunityWizard(context),
        icon: const Icon(Icons.add),
        label: const Text('Create community'),
      ),
    );
  }

  void _showJoinByCodeDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Community'),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            labelText: 'Community ID or invite code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) {
                return;
              }
              await ref
                  .read(communitiesControllerProvider.notifier)
                  .joinByCode(code);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _showCreateCommunityWizard(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isPublic = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Create Community'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: isPublic,
                  onChanged: (value) => setModalState(() => isPublic = value),
                  title: const Text('Public community'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await ref
                    .read(communitiesControllerProvider.notifier)
                    .createCommunity(
                      name: nameController.text.trim(),
                      description: descController.text.trim(),
                      isPublic: isPublic,
                    );
                await ref
                    .read(communitiesControllerProvider.notifier)
                    .loadCommunities();
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class CommunitiesList extends ConsumerWidget {
  final List<Community> communities;

  const CommunitiesList({Key? key, required this.communities})
    : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: communities.length,
      itemBuilder: (context, index) {
        final community = communities[index];
        return CommunityCard(community: community);
      },
    );
  }
}

class CommunityCard extends ConsumerWidget {
  final Community community;

  const CommunityCard({Key? key, required this.community}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => context.push('/app/communities/${community.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(community.icon, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          community.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${community.memberCount} members',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (community.isMember)
                    Chip(
                      label: const Text('Member'),
                      backgroundColor: Colors.green.withValues(alpha: 0.2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                community.description,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (community.isMember)
                    ElevatedButton(
                      onPressed: () {
                        ref
                            .read(communitiesControllerProvider.notifier)
                            .leaveCommunity(community.id);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Leave'),
                    )
                  else
                    ElevatedButton(
                      onPressed: () {
                        ref
                            .read(communitiesControllerProvider.notifier)
                              .joinCommunity(community.id);
                      },
                      child: const Text('Join'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityDetailScreen extends ConsumerStatefulWidget {
  final String communityId;

  const CommunityDetailScreen({Key? key, required this.communityId})
    : super(key: key);

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _loading = true;
  String _searchText = '';
  String _roleFilter = 'all';
  String _departmentFilter = 'all';
  String _statusFilter = 'all';
  String? _myRole;
  List<Map<String, dynamic>> _messages = const [];
  List<Map<String, dynamic>> _members = const [];
  List<Map<String, dynamic>> _departments = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  bool get _canManageMembers {
    final role = (_myRole ?? '').toLowerCase();
    return role == 'owner' || role == 'admin' || role == 'admin_sec';
  }

  String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is Map) {
      if (value['Valid'] == false) {
        return '';
      }
      final inner = value['String'] ?? value['UUID'] ?? value['id'];
      if (inner != null) {
        return inner.toString().trim();
      }
      return '';
    }
    return value.toString().trim();
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  String _memberUserId(Map<String, dynamic> member) {
    final user = _mapOf(member['user']);
    return _readString(member['user_id']).isNotEmpty
        ? _readString(member['user_id'])
        : _readString(user['id']);
  }

  String _memberDisplayName(Map<String, dynamic> member) {
    final user = _mapOf(member['user']);
    final displayName = _readString(user['display_name']);
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final username = _readString(user['username']);
    if (username.isNotEmpty) {
      return username;
    }
    final email = _readString(user['email']);
    if (email.isNotEmpty) {
      return email;
    }
    return _memberUserId(member);
  }

  String _memberUsername(Map<String, dynamic> member) {
    final user = _mapOf(member['user']);
    final username = _readString(user['username']);
    if (username.isNotEmpty) {
      return username;
    }
    return _memberDisplayName(member);
  }

  String _memberEmail(Map<String, dynamic> member) {
    final user = _mapOf(member['user']);
    return _readString(user['email']);
  }

  String _memberDepartmentId(Map<String, dynamic> member) {
    return _readString(member['department_id']);
  }

  String _memberDepartmentName(Map<String, dynamic> member) {
    final departmentId = _memberDepartmentId(member);
    if (departmentId.isEmpty) {
      return 'No department';
    }
    for (final department in _departments) {
      if (_readString(department['id']) == departmentId) {
        final name = _readString(department['name']);
        if (name.isNotEmpty) {
          return name;
        }
      }
    }
    return departmentId;
  }

  String _memberRole(Map<String, dynamic> member) {
    final role = _readString(member['role']);
    return role.isEmpty ? 'member' : role;
  }

  Map<String, dynamic> _memberPresence(Map<String, dynamic> member) {
    return _mapOf(member['presence']);
  }

  String _memberAvailability(Map<String, dynamic> member) {
    final presence = _memberPresence(member);
    final availability = _readString(presence['availability']);
    if (availability.isNotEmpty) {
      return availability.toLowerCase();
    }
    final user = _mapOf(member['user']);
    return (user['is_online'] as bool?) ?? false ? 'online' : 'offline';
  }

  String _memberStatusLabel(Map<String, dynamic> member) {
    final presence = _memberPresence(member);
    final emoji = _readString(presence['emoji']);
    final message = _readString(presence['message']);
    final availability = _memberAvailability(member);
    final capitalized = availability.isEmpty
        ? 'offline'
        : availability[0].toUpperCase() + availability.substring(1);
    final parts = <String>[];
    if (emoji.isNotEmpty) {
      parts.add(emoji);
    }
    parts.add(capitalized);
    if (message.isNotEmpty) {
      parts.add(message);
    }
    return parts.join(' • ');
  }

  bool _canManageTargetRole(String role) {
    final normalized = role.toLowerCase();
    if (!_canManageMembers) {
      return false;
    }
    if (normalized == 'owner' && (_myRole ?? '').toLowerCase() != 'owner') {
      return false;
    }
    return true;
  }

  String _memberNameByUserId(String userId) {
    for (final member in _members) {
      if (_memberUserId(member) == userId) {
        return _memberDisplayName(member);
      }
    }
    return userId;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final controller = ref.read(communitiesControllerProvider.notifier);
    final details = await controller.loadCommunityDetails(widget.communityId);
    final messages = await controller.loadCommunityMessages(widget.communityId);
    if (!mounted) {
      return;
    }
    final members = ((details['members'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from((e as Map?) ?? const {}))
        .toList();
    final departments = ((details['departments'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from((e as Map?) ?? const {}))
        .toList();
    setState(() {
      _messages = messages
        ..sort((a, b) {
          final aTime =
              DateTime.tryParse((a['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime =
              DateTime.tryParse((b['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return aTime.compareTo(bTime);
        });
      _members = members;
      _departments = departments;
      _myRole = _readString(details['my_role']).isEmpty
          ? _myRole
          : _readString(details['my_role']);
      _loading = false;
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }
    await ref
        .read(communitiesControllerProvider.notifier)
        .sendCommunityMessage(widget.communityId, text);
    _messageController.clear();
    await _load();
  }

  Future<void> _sendSessionInvite(String userId, String displayName) async {
    try {
      await ref.read(apiClientProvider).post('/remote/invite/$userId');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite sent to $displayName')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to invite: $e')),
      );
    }
  }

  Future<void> _sendFriendRequest(String userId, String displayName) async {
    try {
      await ref.read(friendsControllerProvider.notifier).sendFriendRequest(userId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to $displayName')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send friend request: $e')),
      );
    }
  }

  Future<void> _generateInviteLink() async {
    try {
      final result = await ref
          .read(communitiesControllerProvider.notifier)
          .generateCommunityInvite(widget.communityId);
      final code = _readString(result['invite_code']);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Community invite'),
          content: SelectableText(code.isEmpty ? 'Invite generated.' : code),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate invite: $e')),
      );
    }
  }

  Future<void> _createDepartment() async {
    final nameController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add department'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Department name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                return;
              }
              try {
                await ref
                    .read(communitiesControllerProvider.notifier)
                    .createCommunityDepartment(
                      communityId: widget.communityId,
                      name: name,
                    );
                if (!mounted) {
                  return;
                }
                Navigator.pop(dialogContext);
                await _load();
              } catch (e) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add department: $e')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _manageMember(Map<String, dynamic> member) async {
    final userId = _memberUserId(member);
    final displayName = _memberDisplayName(member);
    final currentRole = _memberRole(member);
    String selectedRole = currentRole;
    String? selectedDepartmentId = _memberDepartmentId(member).isEmpty
        ? null
        : _memberDepartmentId(member);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Manage role and department for $displayName'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(
                        value: 'admin_sec',
                        child: Text('Security admin'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setSheetState(() => selectedRole = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedDepartmentId,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Keep current'),
                      ),
                      ..._departments.map(
                        (department) => DropdownMenuItem<String?>(
                          value: _readString(department['id']),
                          child: Text(_readString(department['name'])),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setSheetState(() => selectedDepartmentId = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(communitiesControllerProvider.notifier)
                                  .removeCommunityMember(
                                    communityId: widget.communityId,
                                    userId: userId,
                                  );
                              if (!mounted) {
                                return;
                              }
                              Navigator.pop(sheetContext);
                              await _load();
                            } catch (e) {
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to remove member: $e'),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Remove member'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(communitiesControllerProvider.notifier)
                                  .updateCommunityMember(
                                    communityId: widget.communityId,
                                    userId: userId,
                                    role: selectedRole,
                                    departmentId: selectedDepartmentId,
                                  );
                              if (!mounted) {
                                return;
                              }
                              Navigator.pop(sheetContext);
                              await _load();
                            } catch (e) {
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to update member: $e'),
                                ),
                              );
                            }
                          },
                          child: const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMemberActions(
    Map<String, dynamic> member,
    Set<String> friendIds,
    String currentUserId,
  ) {
    final userId = _memberUserId(member);
    if (userId.isEmpty || (currentUserId.isNotEmpty && currentUserId == userId)) {
      return const Chip(label: Text('You'));
    }
    final displayName = _memberDisplayName(member);
    final friend = friendIds.contains(userId);
    final role = _memberRole(member);
    final canManageTarget = _canManageTargetRole(role);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (friend)
          FilledButton.tonal(
            onPressed: _memberAvailability(member) == 'offline'
                ? null
                : () => _sendSessionInvite(userId, displayName),
            child: const Text('Session'),
          )
        else
          FilledButton.tonal(
            onPressed: () => _sendFriendRequest(userId, displayName),
            child: const Text('Add friend'),
          ),
        if (canManageTarget)
          OutlinedButton(
            onPressed: () => _manageMember(member),
            child: const Text('Manage'),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _filteredMembers() {
    final query = _searchText.trim().toLowerCase();
    return _members.where((member) {
      final displayName = _memberDisplayName(member).toLowerCase();
      final username = _memberUsername(member).toLowerCase();
      final email = _memberEmail(member).toLowerCase();
      final role = _memberRole(member).toLowerCase();
      final departmentId = _memberDepartmentId(member);
      final availability = _memberAvailability(member);
      if (query.isNotEmpty &&
          !displayName.contains(query) &&
          !username.contains(query) &&
          !email.contains(query)) {
        return false;
      }
      if (_roleFilter != 'all' && role != _roleFilter) {
        return false;
      }
      if (_departmentFilter != 'all' && departmentId != _departmentFilter) {
        return false;
      }
      if (_statusFilter != 'all' && availability != _statusFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final communitiesState = ref.watch(communitiesControllerProvider);
    final friendsState = ref.watch(friendsControllerProvider);
    final currentUserId = ref.watch(authControllerProvider).user?.id.toString() ?? '';

    final community = communitiesState.communities.firstWhere(
      (c) => c.id == widget.communityId,
      orElse: () => Community(
        id: widget.communityId,
        name: 'Unknown Community',
        description: '',
        icon: '🏢',
        memberCount: 0,
      ),
    );
    final friendIds = friendsState.friends.map((friend) => friend.id).toSet();
    final filteredMembers = _filteredMembers();

    return Scaffold(
      appBar: AppBar(title: Text(community.name)),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        community.icon,
                        style: const TextStyle(fontSize: 48),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              community.name,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              '${community.memberCount} members',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    community.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!community.isMember)
                        ElevatedButton(
                          onPressed: () => ref
                              .read(communitiesControllerProvider.notifier)
                              .joinCommunity(community.id),
                          child: const Text('Join Community'),
                        ),
                      if (_canManageMembers)
                        OutlinedButton(
                          onPressed: _generateInviteLink,
                          child: const Text('Share invite'),
                        ),
                      if (_canManageMembers)
                        OutlinedButton(
                          onPressed: _createDepartment,
                          child: const Text('Add department'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            TabBar(
              tabs: [
                const Tab(text: 'Feed'),
                const Tab(text: 'Members'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            Expanded(
                              child: _messages.isEmpty
                                  ? const Center(child: Text('No messages yet'))
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: _messages.length,
                                      itemBuilder: (context, index) {
                                        final msg = _messages[index];
                                        final createdAt = DateTime.tryParse(
                                          (msg['created_at'] ?? '').toString(),
                                        );
                                        final senderId = _readString(msg['sender_id']);
                                        final senderName = _memberNameByUserId(senderId);
                                        return ListTile(
                                          title: Text(
                                            (msg['content'] ?? '').toString(),
                                          ),
                                          subtitle: Text(
                                            '$senderName • ${createdAt != null ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}' : '-'}',
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _messageController,
                                      decoration: const InputDecoration(
                                        hintText: 'Send a message',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: _sendMessage,
                                    child: const Text('Send'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              child: Column(
                                children: [
                                  TextField(
                                    decoration: const InputDecoration(
                                      labelText: 'Search members',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        _searchText = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      DropdownButton<String>(
                                        value: _roleFilter,
                                        items: const [
                                          DropdownMenuItem(value: 'all', child: Text('All roles')),
                                          DropdownMenuItem(value: 'user', child: Text('User')),
                                          DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                          DropdownMenuItem(value: 'admin_sec', child: Text('Security admin')),
                                          DropdownMenuItem(value: 'owner', child: Text('Owner')),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() => _roleFilter = value);
                                        },
                                      ),
                                      DropdownButton<String>(
                                        value: _departmentFilter,
                                        items: [
                                          const DropdownMenuItem(
                                            value: 'all',
                                            child: Text('All departments'),
                                          ),
                                          const DropdownMenuItem(
                                            value: '',
                                            child: Text('No department'),
                                          ),
                                          ..._departments.map(
                                            (department) => DropdownMenuItem(
                                              value: _readString(department['id']),
                                              child: Text(_readString(department['name'])),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() => _departmentFilter = value);
                                        },
                                      ),
                                      DropdownButton<String>(
                                        value: _statusFilter,
                                        items: const [
                                          DropdownMenuItem(value: 'all', child: Text('All statuses')),
                                          DropdownMenuItem(value: 'online', child: Text('Online')),
                                          DropdownMenuItem(value: 'away', child: Text('Away')),
                                          DropdownMenuItem(value: 'busy', child: Text('Busy')),
                                          DropdownMenuItem(value: 'offline', child: Text('Offline')),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() => _statusFilter = value);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (_canManageMembers)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _generateInviteLink,
                                      icon: const Icon(Icons.ios_share),
                                      label: const Text('Share invite'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _createDepartment,
                                      icon: const Icon(Icons.add_business),
                                      label: const Text('Add department'),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: filteredMembers.isEmpty
                                  ? const Center(child: Text('No members found'))
                                  : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                      itemCount: filteredMembers.length,
                                      separatorBuilder: (context, index) => const Divider(height: 24),
                                      itemBuilder: (context, index) {
                                        final member = filteredMembers[index];
                                        final displayName = _memberDisplayName(member);
                                        final username = _memberUsername(member);
                                        final departmentName = _memberDepartmentName(member);
                                        return ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: CircleAvatar(
                                            child: Text(
                                              displayName.isNotEmpty
                                                  ? displayName.substring(0, 1).toUpperCase()
                                                  : '?',
                                            ),
                                          ),
                                          title: Text(displayName),
                                          subtitle: Text(
                                            '@$username • ${_memberRole(member)} • ${_memberStatusLabel(member)} • $departmentName',
                                          ),
                                          isThreeLine: true,
                                          trailing: _buildMemberActions(
                                            member,
                                            friendIds,
                                            currentUserId,
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
