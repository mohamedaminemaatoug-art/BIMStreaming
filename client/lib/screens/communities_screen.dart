import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/state/auth_controller.dart';
import '../../app/state/data_providers.dart';

// ═══════════════════════════════════════════════════════
// Communities list screen
// ═══════════════════════════════════════════════════════

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(communitiesControllerProvider.notifier).loadCommunities();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communitiesControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communities'),
        actions: [
          IconButton(
            icon: const Icon(Icons.login),
            tooltip: 'Join Community',
            onPressed: () => _showJoinDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(communitiesControllerProvider.notifier).loadCommunities(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
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
              : state.communities.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.groups_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No communities available'),
                        ],
                      ),
                    )
                  : CommunitiesList(communities: state.communities),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Create community'),
      ),
    );
  }

  void _showJoinDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Community'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Community ID or invite code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final code = ctrl.text.trim();
              if (code.isEmpty) return;
              try {
                await ref
                    .read(communitiesControllerProvider.notifier)
                    .joinByCode(code);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Joined community successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to join: $e')),
                  );
                }
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isPublic = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Text('Create Community'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: isPublic,
                  onChanged: (v) => setModal(() => isPublic = v),
                  title: const Text('Public community'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await ref
                    .read(communitiesControllerProvider.notifier)
                    .createCommunity(
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                      isPublic: isPublic,
                    );
                await ref
                    .read(communitiesControllerProvider.notifier)
                    .loadCommunities();
                if (context.mounted) Navigator.pop(ctx);
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
  const CommunitiesList({Key? key, required this.communities}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: communities.length,
      itemBuilder: (_, i) => CommunityCard(community: communities[i]),
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
                      onPressed: () => ref
                          .read(communitiesControllerProvider.notifier)
                          .leaveCommunity(community.id),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Leave'),
                    )
                  else
                    ElevatedButton(
                      onPressed: () => ref
                          .read(communitiesControllerProvider.notifier)
                          .joinCommunity(community.id),
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

// ═══════════════════════════════════════════════════════
// Community detail screen
// ═══════════════════════════════════════════════════════

class CommunityDetailScreen extends ConsumerStatefulWidget {
  final String communityId;
  const CommunityDetailScreen({Key? key, required this.communityId})
      : super(key: key);

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState
    extends ConsumerState<CommunityDetailScreen> {
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

  // ── Permission helpers ──────────────────────────────

  bool get _canManageMembers {
    final r = (_myRole ?? '').toLowerCase();
    return r == 'owner' || r == 'admin' || r == 'admin_sec';
  }

  bool get _isOwner => (_myRole ?? '').toLowerCase() == 'owner';

  bool _canManageTarget(String role) {
    if (!_canManageMembers) return false;
    if (role.toLowerCase() == 'owner' && !_isOwner) return false;
    return true;
  }

  // ── Data parsing helpers ────────────────────────────

  String _readString(dynamic v) {
    if (v == null) return '';
    if (v is Map) {
      if (v['Valid'] == false) return '';
      final inner = v['String'] ?? v['UUID'] ?? v['id'];
      return inner != null ? inner.toString().trim() : '';
    }
    return v.toString().trim();
  }

  Map<String, dynamic> _mapOf(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  bool _looksLikeUuid(String s) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(s.trim());

  // ── Member field accessors ──────────────────────────

  String _memberUserId(Map<String, dynamic> m) {
    final user = _mapOf(m['user']);
    final direct = _readString(m['user_id']);
    return direct.isNotEmpty ? direct : _readString(user['id']);
  }

  String _memberDisplayName(Map<String, dynamic> m) {
    final direct = _readString(m['display_name']);
    if (direct.isNotEmpty) return direct;
    final user = _mapOf(m['user']);
    final dn = _readString(user['display_name']);
    if (dn.isNotEmpty) return dn;
    final un = _readString(user['username']);
    if (un.isNotEmpty && !_looksLikeUuid(un)) return un;
    final email = _readString(user['email']);
    if (email.isNotEmpty) return email;
    final dun = _readString(m['username']);
    if (dun.isNotEmpty && !_looksLikeUuid(dun)) return dun;
    return _memberUserId(m);
  }

  String _memberUsername(Map<String, dynamic> m) {
    final direct = _readString(m['username']);
    if (direct.isNotEmpty && !_looksLikeUuid(direct)) return direct;
    final user = _mapOf(m['user']);
    final un = _readString(user['username']);
    if (un.isNotEmpty && !_looksLikeUuid(un)) return un;
    final dn = _readString(m['display_name']);
    if (dn.isNotEmpty && !_looksLikeUuid(dn)) return dn;
    return _memberUserId(m);
  }

  String _memberEmail(Map<String, dynamic> m) =>
      _readString(_mapOf(m['user'])['email']);

  String _memberDeptId(Map<String, dynamic> m) =>
      _readString(m['department_id']);

  String _memberRole(Map<String, dynamic> m) {
    final r = _readString(m['role']);
    return r.isEmpty ? 'user' : r;
  }

  String _memberAvatarUrl(Map<String, dynamic> m) =>
      _readString(_mapOf(m['user'])['avatar_url']);

  Color _avatarColor(BuildContext ctx, String seed) {
    final colors = [
      Theme.of(ctx).colorScheme.primaryContainer,
      Theme.of(ctx).colorScheme.secondaryContainer,
      Theme.of(ctx).colorScheme.tertiaryContainer,
      Theme.of(ctx).colorScheme.surfaceContainerHighest,
    ];
    if (seed.isEmpty) return colors.first;
    return colors[
        seed.codeUnits.fold<int>(0, (s, c) => s + c) % colors.length];
  }

  String _memberAvailability(Map<String, dynamic> m) {
    final presence = _mapOf(m['presence']);
    final avail = _readString(presence['availability']);
    if (avail.isNotEmpty) return avail.toLowerCase();
    if (m['is_online'] == true) return 'online';
    final user = _mapOf(m['user']);
    return (user['is_online'] as bool?) == true ? 'online' : 'offline';
  }

  String _memberNameById(String userId) {
    for (final m in _members) {
      if (_memberUserId(m) == userId) return _memberDisplayName(m);
    }
    return userId;
  }

  String _deptName(String deptId) {
    if (deptId.isEmpty) return '';
    for (final d in _departments) {
      if (_readString(d['id']) == deptId) return _readString(d['name']);
    }
    return deptId;
  }

  // ── Data loading ────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    final ctrl = ref.read(communitiesControllerProvider.notifier);
    final details = await ctrl.loadCommunityDetails(widget.communityId);
    final msgs = await ctrl.loadCommunityMessages(widget.communityId);
    // Use the enriched members endpoint so username/display_name/presence are populated
    final members = await ctrl.loadCommunityMembers(widget.communityId);
    if (!mounted) return;
    final depts = ((details['departments'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from((e as Map?) ?? const {}))
        .toList();
    setState(() {
      _messages = msgs
        ..sort((a, b) {
          final aT = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bT = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return aT.compareTo(bT);
        });
      _members = members;
      _departments = depts;
      final rawRole = _readString(details['my_role']);
      if (rawRole.isNotEmpty) _myRole = rawRole;
      _loading = false;
    });
  }

  // ── CRUD actions ────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await ref
        .read(communitiesControllerProvider.notifier)
        .sendCommunityMessage(widget.communityId, text);
    _messageController.clear();
    await _load();
  }

  Future<void> _generateInviteLink() async {
    try {
      final result = await ref
          .read(communitiesControllerProvider.notifier)
          .generateCommunityInvite(widget.communityId);
      final code = _readString(result['invite_code']);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Community invite'),
          content: SelectableText(code.isEmpty ? 'Invite generated.' : code),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to generate invite: $e')));
    }
  }

  Future<void> _createDepartment() async {
    final nameCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Department'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Department name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              try {
                await ref
                    .read(communitiesControllerProvider.notifier)
                    .createCommunityDepartment(
                      communityId: widget.communityId,
                      name: name,
                    );
                if (!mounted) return;
                Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Failed: $e')));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDepartment(String deptId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Department'),
        content: const Text(
            'Members in this department will become unassigned. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(communitiesControllerProvider.notifier)
          .deleteCommunityDepartment(
            communityId: widget.communityId,
            departmentId: deptId,
          );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _addMemberToDepartment(String deptId) async {
    final available = _members
        .where((m) =>
            _memberRole(m) != 'owner' && _memberDeptId(m) != deptId)
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No available members to assign')));
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add to ${_deptName(deptId)}'),
        content: SizedBox(
          width: 380,
          height: 320,
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (_, i) {
              final m = available[i];
              final name = _memberDisplayName(m);
              final role = _memberRole(m);
              final currentDept = _memberDeptId(m);
              return ListTile(
                leading: _memberAvatarWidget(m),
                title: Text(name),
                subtitle: Text(currentDept.isEmpty
                    ? 'Unassigned'
                    : _deptName(currentDept)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await ref
                        .read(communitiesControllerProvider.notifier)
                        .updateCommunityMember(
                          communityId: widget.communityId,
                          userId: _memberUserId(m),
                          role: role,
                          departmentId: deptId,
                        );
                    await _load();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Failed: $e')));
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _manageMember(Map<String, dynamic> member) async {
    final userId = _memberUserId(member);
    final displayName = _memberDisplayName(member);
    final currentRole = _memberRole(member);
    String selectedRole = currentRole;
    String? selectedDeptId =
        _memberDeptId(member).isEmpty ? null : _memberDeptId(member);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName,
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
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
                      value: 'admin_sec', child: Text('Security admin')),
                ],
                onChanged: (v) {
                  if (v != null) setSheet(() => selectedRole = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: selectedDeptId,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('No department')),
                  ..._departments.map((d) => DropdownMenuItem<String?>(
                        value: _readString(d['id']),
                        child: Text(_readString(d['name'])),
                      )),
                ],
                onChanged: (v) => setSheet(() => selectedDeptId = v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
                      onPressed: () async {
                        try {
                          await ref
                              .read(communitiesControllerProvider.notifier)
                              .removeCommunityMember(
                                communityId: widget.communityId,
                                userId: userId,
                              );
                          if (!mounted) return;
                          Navigator.pop(sheetCtx);
                          await _load();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e')));
                        }
                      },
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
                                departmentId: selectedDeptId,
                              );
                          if (!mounted) return;
                          Navigator.pop(sheetCtx);
                          await _load();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e')));
                        }
                      },
                      child: const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final name = _memberDisplayName(member);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $name from this community?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(communitiesControllerProvider.notifier)
          .removeCommunityMember(
            communityId: widget.communityId,
            userId: _memberUserId(member),
          );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _openSessionInvite(Map<String, dynamic> m) async {
    final userId = _memberUserId(m);
    final name = _memberDisplayName(m);
    if (userId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remote Session'),
        content: Text('Send a remote session invite to $name?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send Invite')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiClientProvider).post('/remote/invite/$userId');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remote invite sent to $name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send invite: $e')),
      );
    }
  }

  Future<void> _showInviteOptions() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Share invite code'),
              subtitle: const Text('Copy a code others can use to join'),
              onTap: () {
                Navigator.pop(ctx);
                _generateInviteLink();
              },
            ),
            if (_canManageMembers)
              ListTile(
                leading: const Icon(Icons.person_add_outlined),
                title: const Text('Add member by email'),
                subtitle: const Text('Find a registered user and add them directly'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddByEmailDialog();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showAddByEmailDialog() async {
    final emailCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Member by Email'),
        content: TextField(
          controller: emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'user@example.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              try {
                await ref
                    .read(communitiesControllerProvider.notifier)
                    .addCommunityMemberByEmail(
                      communityId: widget.communityId,
                      email: email,
                    );
                if (!mounted) return;
                Navigator.pop(ctx);
                await _load();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$email added to community')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed: $e')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ── Filtering ───────────────────────────────────────

  List<Map<String, dynamic>> _filteredMembers() {
    final q = _searchText.trim().toLowerCase();
    return _members.where((m) {
      final dn = _memberDisplayName(m).toLowerCase();
      final un = _memberUsername(m).toLowerCase();
      final em = _memberEmail(m).toLowerCase();
      if (q.isNotEmpty &&
          !dn.contains(q) &&
          !un.contains(q) &&
          !em.contains(q)) return false;
      if (_roleFilter != 'all' && _memberRole(m) != _roleFilter) return false;
      if (_departmentFilter != 'all' &&
          _memberDeptId(m) != _departmentFilter) return false;
      if (_statusFilter != 'all' &&
          _memberAvailability(m) != _statusFilter) return false;
      return true;
    }).toList();
  }

  // ── Shared UI atoms ─────────────────────────────────

  Widget _memberAvatarWidget(Map<String, dynamic> m) {
    final name = _memberDisplayName(m);
    final url = _memberAvatarUrl(m);
    final seed = _memberUsername(m).isNotEmpty ? _memberUsername(m) : name;
    return CircleAvatar(
      radius: 20,
      backgroundColor: _avatarColor(context, seed),
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            )
          : null,
    );
  }

  Widget _statusBadge(String availability) {
    Color color;
    String label;
    switch (availability) {
      case 'online':
        color = Colors.green;
        label = 'Online';
      case 'away':
        color = Colors.orange;
        label = 'Away';
      case 'busy':
        color = Colors.red;
        label = 'Busy';
      default:
        color = Colors.grey;
        label = 'Offline';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _roleBadge(String role) {
    Color color;
    String label;
    switch (role.toLowerCase()) {
      case 'owner':
        color = Colors.amber;
        label = 'Owner';
      case 'admin':
        color = const Color(0xFF4A9EFF);
        label = 'Admin';
      case 'admin_sec':
        color = Colors.purple;
        label = 'Admin Sec';
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _pillDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          borderRadius: BorderRadius.circular(8),
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }

  // ── Member card/row builders ─────────────────────────

  Widget _ownerCard(
      Map<String, dynamic> m, Set<String> friendIds, String currentUserId) {
    final name = _memberDisplayName(m);
    final username = _memberUsername(m);
    final avail = _memberAvailability(m);
    final userId = _memberUserId(m);
    final isMe = userId == currentUserId;

    return GestureDetector(
      onTap: isMe ? null : () => _openSessionInvite(m),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Colors.amber.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _crownCircle(Colors.amber),
            const SizedBox(width: 10),
            _memberAvatarWidget(m),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  if (username.isNotEmpty && username != name)
                    Text('@$username',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.primary,
                            fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      _roleBadge('owner'),
                      _statusBadge(avail),
                      if (isMe)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('You',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isMe) ...[
              const SizedBox(width: 8),
              const Icon(Icons.star, color: Colors.amber, size: 20),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _adminCard(
      Map<String, dynamic> m, Set<String> friendIds, String currentUserId) {
    final name = _memberDisplayName(m);
    final username = _memberUsername(m);
    final role = _memberRole(m);
    final userId = _memberUserId(m);
    final isMe = userId == currentUserId;
    final canManage = _canManageTarget(role);
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: isMe ? null : () => _openSessionInvite(m),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _crownCircle(primary),
            const SizedBox(width: 10),
            _memberAvatarWidget(m),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  if (username.isNotEmpty && username != name)
                    Text('@$username',
                        style: TextStyle(
                            color: primary, fontSize: 11)),
                ],
              ),
            ),
            if (isMe)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('You',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey)),
              )
            else ...[
              _roleBadge(role),
              if (canManage) ...[
                const SizedBox(width: 4),
                _iconAction(
                    icon: Icons.manage_accounts,
                    tooltip: 'Manage',
                    onTap: () => _manageMember(m)),
              ],
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _memberRow(
      Map<String, dynamic> m, Set<String> friendIds, String currentUserId) {
    final name = _memberDisplayName(m);
    final role = _memberRole(m);
    final avail = _memberAvailability(m);
    final userId = _memberUserId(m);
    final isMe = userId == currentUserId;
    final canManage = _canManageTarget(role);
    final roleCap = role.isEmpty
        ? 'Member'
        : role[0].toUpperCase() + role.substring(1);

    return GestureDetector(
      onTap: isMe ? null : () => _openSessionInvite(m),
      child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            _personCircle(),
            const SizedBox(width: 8),
            _memberAvatarWidget(m),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(roleCap,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            ),
            if (isMe)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('You',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey)),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _statusBadge(avail),
                  if (canManage) ...[
                    const SizedBox(width: 4),
                    _iconAction(
                        icon: Icons.arrow_upward,
                        tooltip: 'Manage',
                        onTap: () => _manageMember(m)),
                    _iconAction(
                        icon: Icons.close,
                        tooltip: 'Remove',
                        color: Colors.red,
                        onTap: () => _removeMember(m)),
                  ],
                ],
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _crownCircle(Color color) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.workspace_premium, color: color, size: 16),
      );

  Widget _personCircle() => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person, color: Colors.grey, size: 14),
      );

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) =>
      SizedBox(
        width: 30,
        height: 30,
        child: IconButton(
          icon: Icon(icon, size: 16, color: color),
          tooltip: tooltip,
          onPressed: onTap,
          padding: EdgeInsets.zero,
        ),
      );

  Widget _unassignedSection(
      List<Map<String, dynamic>> members,
      Set<String> friendIds,
      String currentUserId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.person_outline, color: Colors.grey.shade500, size: 15),
            const SizedBox(width: 6),
            Text('Unassigned',
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        ...members.map((m) {
          final r = _memberRole(m);
          return (r == 'admin' || r == 'admin_sec')
              ? _adminCard(m, friendIds, currentUserId)
              : _memberRow(m, friendIds, currentUserId);
        }),
      ],
    );
  }

  // ── Main build ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final commState = ref.watch(communitiesControllerProvider);
    final friendsState = ref.watch(friendsControllerProvider);
    final currentUserId =
        ref.watch(authControllerProvider).user?.id.toString() ?? '';

    final community = commState.communities.firstWhere(
      (c) => c.id == widget.communityId,
      orElse: () => Community(
        id: widget.communityId,
        name: 'Community',
        description: '',
        icon: '🏢',
        memberCount: 0,
      ),
    );
    final friendIds = friendsState.friends.map((f) => f.id).toSet();
    final filtered = _filteredMembers();

    // Group for hierarchical view
    final owners = filtered.where((m) => _memberRole(m) == 'owner').toList();
    final nonOwners =
        filtered.where((m) => _memberRole(m) != 'owner').toList();
    final Map<String, List<Map<String, dynamic>>> byDept = {};
    final List<Map<String, dynamic>> unassigned = [];
    for (final m in nonOwners) {
      final id = _memberDeptId(m);
      if (id.isEmpty) {
        unassigned.add(m);
      } else {
        byDept.putIfAbsent(id, () => []).add(m);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(community.name)),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            // Community info header
            Container(
              color: Theme.of(context).colorScheme.surfaceContainer,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(community.icon,
                          style: const TextStyle(fontSize: 40)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(community.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall),
                            Text('${community.memberCount} members',
                                style:
                                    Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (community.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(community.description,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
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
                    ],
                  ),
                ],
              ),
            ),
            const TabBar(
              tabs: [Tab(text: 'Feed'), Tab(text: 'Members')],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // ── Feed tab ──────────────────────────
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            Expanded(
                              child: _messages.isEmpty
                                  ? const Center(
                                      child: Text('No messages yet'))
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: _messages.length,
                                      itemBuilder: (ctx, i) {
                                        final msg = _messages[i];
                                        final at = DateTime.tryParse(
                                            (msg['created_at'] ?? '')
                                                .toString());
                                        final senderName = _memberNameById(
                                            _readString(msg['sender_id']));
                                        return ListTile(
                                          title: Text(
                                              (msg['content'] ?? '')
                                                  .toString()),
                                          subtitle: Text(
                                            '$senderName • ${at != null ? '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}' : '-'}',
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
                                      child: const Text('Send')),
                                ],
                              ),
                            ),
                          ],
                        ),

                  // ── Members tab ───────────────────────
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            // Search bar
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText:
                                      'Search by name, ID or department...',
                                  prefixIcon:
                                      const Icon(Icons.search, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                  filled: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          vertical: 10, horizontal: 12),
                                ),
                                onChanged: (v) =>
                                    setState(() => _searchText = v),
                              ),
                            ),
                            // Filter row
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _pillDropdown<String>(
                                      value: _departmentFilter,
                                      items: [
                                        const DropdownMenuItem(
                                            value: 'all',
                                            child:
                                                Text('All Departments')),
                                        const DropdownMenuItem(
                                            value: '',
                                            child:
                                                Text('No department')),
                                        ..._departments.map((d) =>
                                            DropdownMenuItem(
                                              value:
                                                  _readString(d['id']),
                                              child: Text(
                                                _readString(d['name']),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            )),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() =>
                                              _departmentFilter = v);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _pillDropdown<String>(
                                      value: _roleFilter,
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'all',
                                            child: Text('All Roles')),
                                        DropdownMenuItem(
                                            value: 'owner',
                                            child: Text('Owner')),
                                        DropdownMenuItem(
                                            value: 'admin',
                                            child: Text('Admin')),
                                        DropdownMenuItem(
                                            value: 'admin_sec',
                                            child: Text('Admin Sec')),
                                        DropdownMenuItem(
                                            value: 'user',
                                            child: Text('User')),
                                        DropdownMenuItem(
                                            value: 'viewer',
                                            child: Text('Viewer')),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _roleFilter = v);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _pillDropdown<String>(
                                      value: _statusFilter,
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'all',
                                            child: Text('All Status')),
                                        DropdownMenuItem(
                                            value: 'online',
                                            child: Text('Online')),
                                        DropdownMenuItem(
                                            value: 'away',
                                            child: Text('Away')),
                                        DropdownMenuItem(
                                            value: 'busy',
                                            child: Text('Busy')),
                                        DropdownMenuItem(
                                            value: 'offline',
                                            child: Text('Offline')),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(
                                              () => _statusFilter = v);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Admin action row
                            if (_canManageMembers)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 0, 16, 10),
                                child: Row(
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: _createDepartment,
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.add, size: 16),
                                          SizedBox(width: 4),
                                          Text('Create Department'),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: _showInviteOptions,
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.ios_share, size: 16),
                                          SizedBox(width: 4),
                                          Text('Invite'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Hierarchical members list
                            Expanded(
                              child: filtered.isEmpty
                                  ? const Center(
                                      child: Text('No members found'))
                                  : ListView(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 4, 16, 16),
                                      children: [
                                        // Owners
                                        ...owners.map((m) => _ownerCard(
                                            m,
                                            friendIds,
                                            currentUserId)),
                                        if (owners.isNotEmpty)
                                          const SizedBox(height: 6),
                                        // Departments
                                        ..._departments.where((dept) {
                                          final id =
                                              _readString(dept['id']);
                                          return _departmentFilter ==
                                                  'all' ||
                                              _departmentFilter == id;
                                        }).map((dept) {
                                          final deptId =
                                              _readString(dept['id']);
                                          final deptName =
                                              _readString(dept['name']);
                                          final deptMembers =
                                              byDept[deptId] ?? [];
                                          return _DepartmentSection(
                                            key: ValueKey(deptId),
                                            departmentId: deptId,
                                            departmentName: deptName,
                                            members: deptMembers,
                                            canManage: _canManageMembers,
                                            onDelete: () =>
                                                _deleteDepartment(deptId),
                                            onAddMember: () =>
                                                _addMemberToDepartment(
                                                    deptId),
                                            adminCardBuilder: (m) =>
                                                _adminCard(m, friendIds,
                                                    currentUserId),
                                            memberRowBuilder: (m) =>
                                                _memberRow(m, friendIds,
                                                    currentUserId),
                                            memberRoleGetter: _memberRole,
                                          );
                                        }),
                                        // Unassigned
                                        if ((_departmentFilter == 'all' ||
                                                _departmentFilter == '') &&
                                            unassigned.isNotEmpty)
                                          _unassignedSection(unassigned,
                                              friendIds, currentUserId),
                                      ],
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

// ═══════════════════════════════════════════════════════
// Department section — collapsible
// ═══════════════════════════════════════════════════════

class _DepartmentSection extends StatefulWidget {
  final String departmentId;
  final String departmentName;
  final List<Map<String, dynamic>> members;
  final bool canManage;
  final VoidCallback onDelete;
  final VoidCallback onAddMember;
  final Widget Function(Map<String, dynamic>) adminCardBuilder;
  final Widget Function(Map<String, dynamic>) memberRowBuilder;
  final String Function(Map<String, dynamic>) memberRoleGetter;

  const _DepartmentSection({
    Key? key,
    required this.departmentId,
    required this.departmentName,
    required this.members,
    required this.canManage,
    required this.onDelete,
    required this.onAddMember,
    required this.adminCardBuilder,
    required this.memberRowBuilder,
    required this.memberRoleGetter,
  }) : super(key: key);

  @override
  State<_DepartmentSection> createState() => _DepartmentSectionState();
}

class _DepartmentSectionState extends State<_DepartmentSection> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final admins = widget.members
        .where((m) =>
            widget.memberRoleGetter(m) == 'admin' ||
            widget.memberRoleGetter(m) == 'admin_sec')
        .toList();
    final regulars = widget.members
        .where((m) =>
            widget.memberRoleGetter(m) != 'admin' &&
            widget.memberRoleGetter(m) != 'admin_sec')
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outline
                .withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              children: [
                const Text('📁', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.departmentName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.canManage) ...[
                  _headerBtn(
                    label: 'Add',
                    color: Theme.of(context).colorScheme.primary,
                    onTap: widget.onAddMember,
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      icon: const Icon(Icons.delete,
                          size: 16, color: Colors.red),
                      tooltip: 'Delete department',
                      onPressed: widget.onDelete,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    icon: Icon(
                      _collapsed ? Icons.expand_more : Icons.expand_less,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _collapsed = !_collapsed),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          // Members body
          if (!_collapsed) ...[
            Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                children: [
                  if (widget.members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No members assigned to this department',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ),
                  ...admins.map((m) => widget.adminCardBuilder(m)),
                  ...regulars.map((m) => widget.memberRowBuilder(m)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      );
}
