import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/state/app_strings.dart';
import '../app/state/appearance_controller.dart';
import '../app/state/auth_controller.dart';
import '../../app/state/data_providers.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Friend> _searchResults = const <Friend>[];
  bool _searching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Load friends on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(friendsControllerProvider.notifier).loadFriends();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref.watch(localeProvider));
    final friendsState = ref.watch(friendsControllerProvider);
    ref.listen<AsyncValue<WSMessage>>(wsProvider, (previous, next) {
      next.whenData((event) {
        if (event.type != 'friend:request') {
          if (event.type == 'user:online' || event.type == 'user:offline') {
            final userId = (event.data['user_id'] ?? '').toString();
            if (userId.isNotEmpty) {
              ref
                  .read(friendsControllerProvider.notifier)
                  .updateFriendOnlineStatus(userId, event.type == 'user:online');
            }
          }
          return;
        }
        final requesterId = (event.data['requester_id'] ?? '').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.newFriendRequestFrom}$requesterId')),
        );
        ref.read(friendsControllerProvider.notifier).loadFriends();
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.friendsScreenTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: '${strings.friendsScreenTitle} (${friendsState.friends.length})',
              icon: const Icon(Icons.people),
            ),
            Tab(
              text: '${strings.requests} (${friendsState.pending.length})',
              icon: const Icon(Icons.person_add),
            ),
            Tab(
              text: '${strings.blocked} (${friendsState.blocked.length})',
              icon: const Icon(Icons.block),
            ),
          ],
        ),
      ),
      body: friendsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : friendsState.error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(strings.friendsLoadingError),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      friendsState.error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(friendsControllerProvider.notifier)
                        .loadFriends(),
                    child: Text(strings.retry),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                FriendsList(friends: friendsState.friends),
                FriendRequestsList(pending: friendsState.pending),
                BlockedList(blocked: friendsState.blocked),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddFriendDialog(context),
        icon: const Icon(Icons.person_add),
        label: Text(strings.addFriendTitle),
      ),
    );
  }

  void _showAddFriendDialog(BuildContext context) {
    final controller = TextEditingController();
    final currentUserId =
        ref.read(authControllerProvider).user?.id.toString().trim() ?? '';
    final strings = AppStrings.of(ref.read(localeProvider));
    Future<void> runSearch(StateSetter setModalState) async {
      setModalState(() {
        _searching = true;
        _hasSearched = true;
      });
      try {
        final results = await ref
            .read(friendsControllerProvider.notifier)
            .searchUsers(controller.text);
        setModalState(() {
          _searchResults = results.where((u) => u.id != currentUserId).toList();
          _searching = false;
        });
      } catch (e) {
        setModalState(() {
          _searching = false;
        });
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(strings.addFriendTitle),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => runSearch(setModalState),
                  decoration: InputDecoration(
                    hintText: strings.searchPlaceholder,
                    suffixIcon: IconButton(
                      onPressed: _searching ? null : () => runSearch(setModalState),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                else if (!_hasSearched)
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(strings.searchHint),
                  )
                else if (_searchResults.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(strings.noUsersFound),
                  )
                else
                  SizedBox(
                    height: 240,
                    child: ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        final displayName = user.name.trim().isEmpty
                            ? 'Unknown user'
                            : user.name.trim();
                        final subtitle = user.email.trim().isNotEmpty
                          ? user.email.trim()
                          : 'User ID: ${user.id}';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: user.avatar.isNotEmpty
                                ? NetworkImage(user.avatar)
                                : null,
                            child: user.avatar.isEmpty
                                ? Text(displayName[0].toUpperCase())
                                : null,
                          ),
                          title: Text(displayName),
                          subtitle: Text(subtitle),
                          trailing: FilledButton(
                            onPressed: () async {
                              final controller = ref.read(
                                friendsControllerProvider.notifier,
                              );
                              await controller.sendFriendRequest(user.id);
                              final error = ref.read(
                                friendsControllerProvider,
                              ).error;
                              if (!context.mounted) {
                                return;
                              }
                              if (error != null && error.isNotEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error)),
                                );
                                return;
                              }
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(strings.friendRequestSent)),
                              );
                            },
                            child: Text(strings.addFriendTitle),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _searching ? null : () => runSearch(setModalState),
                    icon: const Icon(Icons.search),
                    label: Text(strings.searchButton),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.closeButton),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendsList extends ConsumerWidget {
  final List<Friend> friends;

  const FriendsList({Key? key, required this.friends}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(ref.watch(localeProvider));
    if (friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(strings.noFriendsYet),
            const SizedBox(height: 8),
            Text(strings.tapToAddFriends, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
      final statusLabel = _friendStatusLabel(friend, strings);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: friend.isOnline
                ? Colors.green
                : Colors.grey.shade300,
            child: friend.avatar.isNotEmpty
                ? Image.network(friend.avatar, fit: BoxFit.cover)
                : Text(friend.name[0].toUpperCase()),
          ),
          title: Text(friend.name),
          subtitle: Text(
            _friendSubtitle(friend, statusLabel),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: strings.message,
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => context.push('/app/messages/${friend.id}'),
              ),
              IconButton(
                tooltip: strings.sendSession,
                icon: const Icon(Icons.videocam_outlined),
                onPressed: () => _sendSessionInvite(
                  context,
                  ref,
                  friend,
                  strings,
                ),
              ),
              PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: Text(strings.message),
                    onTap: () => context.push('/dm/${friend.id}'),
                  ),
                  PopupMenuItem(
                    child: Text(strings.block),
                    onTap: () => ref
                        .read(friendsControllerProvider.notifier)
                        .blockUser(friend.id),
                  ),
                  PopupMenuItem(
                    child: Text(strings.remove),
                    onTap: () => ref
                        .read(friendsControllerProvider.notifier)
                        .removeFriend(friend.id),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
  String _friendStatusLabel(Friend friend, AppStrings strings) {
    switch (friend.availability) {
      case 'away':
        return strings.away;
      case 'busy':
        return strings.busy;
      case 'offline':
        return strings.offline;
      default:
        return friend.isOnline ? strings.online : strings.offline;
    }
  }

  String _friendSubtitle(Friend friend, String statusLabel) {
    final message = friend.statusMessage.trim();
    if (message.isNotEmpty && friend.statusEmoji.trim().isNotEmpty) {
      return '${friend.statusEmoji.trim()} $statusLabel · $message';
    }
    if (message.isNotEmpty) {
      return '$statusLabel · $message';
    }
    if (friend.lastSeen != null && friend.availability == 'offline') {
      return '$statusLabel · Last seen ${_formatTime(friend.lastSeen!)}';
    }
    return statusLabel;
  }

  Future<void> _sendSessionInvite(
    BuildContext context,
    WidgetRef ref,
    Friend friend,
    AppStrings strings,
  ) async {
    try {
      await ref
          .read(friendsControllerProvider.notifier)
          .sendRemoteSessionInvite(friend.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.sessionInviteSent}: ${friend.name}')),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class FriendRequestsList extends ConsumerWidget {
  final List<Friend> pending;

  const FriendRequestsList({Key? key, required this.pending}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(ref.watch(localeProvider));
    if (pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add_alt_1, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(strings.noFriendRequests),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: pending.length,
      itemBuilder: (context, index) {
        final friend = pending[index];
        return ListTile(
          leading: CircleAvatar(
            child: friend.avatar.isNotEmpty
                ? Image.network(friend.avatar, fit: BoxFit.cover)
                : Text(friend.name[0].toUpperCase()),
          ),
          title: Text(friend.name),
          subtitle: friend.email.isNotEmpty ? Text(friend.email) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: () => ref
                    .read(friendsControllerProvider.notifier)
                    .acceptFriendRequest(friend.id),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => ref
                    .read(friendsControllerProvider.notifier)
                    .declineFriendRequest(friend.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BlockedList extends ConsumerWidget {
  final List<Friend> blocked;

  const BlockedList({Key? key, required this.blocked}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(ref.watch(localeProvider));
    if (blocked.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(strings.noBlockedUsers),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: blocked.length,
      itemBuilder: (context, index) {
        final user = blocked[index];
        return ListTile(
          leading: CircleAvatar(
            child: user.avatar.isNotEmpty
                ? Image.network(user.avatar, fit: BoxFit.cover)
                : Text(user.name[0].toUpperCase()),
          ),
          title: Text(user.name),
          subtitle: user.email.isNotEmpty ? Text(user.email) : null,
          trailing: IconButton(
            icon: const Icon(Icons.undo),
            onPressed: () => _showUnblockDialog(context, user, ref, strings),
          ),
        );
      },
    );
  }

  void _showUnblockDialog(
    BuildContext context,
    Friend user,
    WidgetRef ref,
    AppStrings strings,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.unblockUser),
        content: Text('${strings.unblock} ${user.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(friendsControllerProvider.notifier).unblockUser(user.id);
            },
            child: Text(strings.unblock),
          ),
        ],
      ),
    );
  }
}
