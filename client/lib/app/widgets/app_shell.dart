import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/auth_controller.dart';
import '../state/appearance_controller.dart';
import '../state/realtime_controller.dart';
import '../state/data_providers.dart';
import '../state/app_strings.dart';
import 'app_avatar.dart';
import '../../screens/remote_support_page.dart';

class _PendingRemoteInvite {
  const _PendingRemoteInvite({
    required this.inviteId,
    required this.requesterId,
    required this.requesterName,
    required this.requesterAvatarUrl,
    required this.targetDeviceId,
    required this.expiresAt,
  });

  final String inviteId;
  final String requesterId;
  final String requesterName;
  final String requesterAvatarUrl;
  final String targetDeviceId;
  final DateTime expiresAt;
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _expanded = false;
  bool _isRemoteSessionOpen = false;
  _PendingRemoteInvite? _pendingInvite;
  Duration _inviteRemaining = Duration.zero;
  Timer? _inviteTimer;
  String? _inviteActionError;

  @override
  void initState() {
    super.initState();
    // Initialize WebSocket handlers after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(realtimeControllerProvider.notifier).setupWSHandlers();
      // Load initial data when user is authenticated
      ref.read(friendsControllerProvider.notifier).loadFriends();
      ref.read(messagesControllerProvider.notifier).loadConversations();
      ref.read(communitiesControllerProvider.notifier).loadCommunities();
      ref.read(notificationsControllerProvider.notifier).loadNotifications();
      ref.read(remoteSessionsControllerProvider.notifier).loadSessions();
    });
  }

  @override
  void dispose() {
    _inviteTimer?.cancel();
    super.dispose();
  }

  void _startInviteCountdown() {
    _inviteTimer?.cancel();
    _inviteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final invite = _pendingInvite;
      if (invite == null) {
        _inviteTimer?.cancel();
        return;
      }
      final remaining = invite.expiresAt.difference(DateTime.now().toUtc());
      if (!mounted) {
        return;
      }
      if (remaining <= Duration.zero) {
        setState(() {
          _pendingInvite = null;
          _inviteRemaining = Duration.zero;
          _inviteActionError = null;
        });
        _inviteTimer?.cancel();
      } else {
        setState(() {
          _inviteRemaining = remaining;
        });
      }
    });
  }

  Future<void> _handleRemoteInvite(WSMessage message) async {
    final data = message.data;
    final inviteId = (data['invite_id'] ?? '').toString();
    final requesterId = (data['requester_id'] ?? '').toString();
    if (inviteId.isEmpty || requesterId.isEmpty) {
      return;
    }

    final expiresRaw = data['expires_at']?.toString();
    DateTime expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 2));
    if (expiresRaw != null && expiresRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(expiresRaw);
      if (parsed != null) {
        expiresAt = parsed.toUtc();
      }
    }

    String requesterName = 'Incoming request';
    String requesterAvatarUrl = '';
    try {
      final profile = await ref
          .read(apiClientProvider)
          .get('/users/$requesterId');
      requesterName =
          (profile['username'] ?? profile['display_name'] ?? 'Incoming request')
              .toString();
      requesterAvatarUrl = (profile['avatar_url'] ?? '').toString();
    } catch (_) {
      // Keep fallback name/avatar when profile lookup fails.
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _pendingInvite = _PendingRemoteInvite(
        inviteId: inviteId,
        requesterId: requesterId,
        requesterName: requesterName,
        requesterAvatarUrl: requesterAvatarUrl,
        targetDeviceId: (data['target_device_id'] ?? '').toString(),
        expiresAt: expiresAt,
      );
      _inviteRemaining = expiresAt.difference(DateTime.now().toUtc());
      _inviteActionError = null;
    });
    _startInviteCountdown();
  }

  Future<void> _resolveInvite(String action) async {
    final invite = _pendingInvite;
    if (invite == null) {
      return;
    }

    try {
      final result = await ref
          .read(apiClientProvider)
          .patch('/remote/invite/${invite.inviteId}', body: {'action': action});

      if (!mounted) {
        return;
      }
      setState(() {
        _pendingInvite = null;
        _inviteActionError = null;
      });

      if (action == 'accept') {
        final sessionToken = _extractSessionToken(result);
        if (sessionToken.isNotEmpty) {
          _openRemoteSession(
            peerName: invite.requesterName,
            peerUserId: invite.requesterId,
            sessionToken: sessionToken,
            sendLocalScreen: true,
          );
        }
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inviteActionError = e.toString();
      });
    }
  }

  String _extractSessionToken(Map<String, dynamic> payload) {
    final topLevel = (payload['session_token'] ?? '').toString().trim();
    if (topLevel.isNotEmpty && topLevel != 'null') {
      return topLevel;
    }

    final invite = payload['invite'];
    if (invite is Map) {
      final nested = invite['session_token'];
      if (nested is String) {
        final value = nested.trim();
        if (value.isNotEmpty && value != 'null') {
          return value;
        }
      }
      if (nested is Map) {
        final value = (nested['String'] ?? nested['string'] ?? '')
            .toString()
            .trim();
        final valid = nested['Valid'] == true || nested['valid'] == true;
        if (valid && value.isNotEmpty) {
          return value;
        }
      }
    }

    return '';
  }

  void _openRemoteSession({
    required String peerName,
    required String peerUserId,
    required String sessionToken,
    required bool sendLocalScreen,
  }) {
    if (!mounted || _isRemoteSessionOpen || peerUserId.trim().isEmpty) {
      return;
    }
    final auth = ref.read(authControllerProvider);
    _isRemoteSessionOpen = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (context) => RemoteSupportPage(
              deviceName: peerName,
              deviceId: peerUserId,
              sendLocalScreen: sendLocalScreen,
              sessionId: sessionToken,
              currentUserId: auth.user?.id,
              signalingService: ref.read(signalingClientProvider),
              isDarkMode: Theme.of(context).brightness == Brightness.dark,
              translate: (value) => value,
            ),
          ),
        )
        .whenComplete(() {
          _isRemoteSessionOpen = false;
        });
  }

  void _handleInviteAccepted(WSMessage message) {
    final data = message.data;
    final sessionToken = (data['session_token'] ?? '').toString().trim();
    final targetUserId = (data['target_user_id'] ?? '').toString().trim();
    if (sessionToken.isEmpty || targetUserId.isEmpty) {
      return;
    }
    _openRemoteSession(
      peerName: 'Remote host',
      peerUserId: targetUserId,
      sessionToken: sessionToken,
      sendLocalScreen: false,
    );
  }

  void _handleInviteRejected() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Remote invite was declined')),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      // If signed out, reset all data
      if (!next.isAuthenticated) {
        // Could clear providers here if needed
      }
    });

    final auth = ref.watch(authControllerProvider);
    final locale = ref.watch(localeProvider);
    final strings = AppStrings.of(locale);
    ref.listen<AsyncValue<WSMessage>>(wsProvider, (previous, next) {
      next.whenData((message) {
        if (message.type == 'remote:invite') {
          _handleRemoteInvite(message);
          return;
        }
        if (message.type == 'remote:invite_accepted') {
          _handleInviteAccepted(message);
          return;
        }
        if (message.type == 'remote:invite_rejected') {
          _handleInviteRejected();
          return;
        }
        if (message.type == 'dm:new' &&
            !widget.location.startsWith('/app/messages')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('You have a new message'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () => context.go('/app/messages'),
              ),
            ),
          );
          return;
        }
        if (message.type == 'notification:new') {
          final title =
              message.data['title']?.toString() ?? 'New notification';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(title),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'View',
                onPressed: () => context.go('/app/notifications'),
              ),
            ),
          );
        }
      });
    });

    final navItems = <({IconData icon, String label, String route})>[
      (icon: Icons.home_outlined, label: strings.home, route: '/app/home'),
      (icon: Icons.person_outline, label: strings.profile, route: '/app/profile'),
      (icon: Icons.group_outlined, label: strings.friends, route: '/app/friends'),
      (
        icon: Icons.chat_bubble_outline,
        label: strings.messages,
        route: '/app/messages',
      ),
      (
        icon: Icons.hub_outlined,
        label: strings.communities,
        route: '/app/communities',
      ),
      (
        icon: Icons.notifications_outlined,
        label: strings.notifications,
        route: '/app/notifications',
      ),
      (
        icon: Icons.settings_outlined,
        label: strings.settings,
        route: '/app/settings',
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: _expanded ? 240 : 72,
                color: const Color(0xFF101C26),
                child: SafeArea(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () =>
                                  setState(() => _expanded = !_expanded),
                              icon: const Icon(Icons.menu, color: Colors.white),
                            ),
                            if (_expanded)
                              const Text(
                                'BimStreaming',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (final item in navItems)
                        _NavItem(
                          expanded: _expanded,
                          active: widget.location.startsWith(item.route),
                          icon: item.icon,
                          label: item.label,
                          onTap: () => context.go(item.route),
                        ),
                      const Spacer(),
                      if (auth.user != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              AppAvatar(name: auth.user!.name, radius: 14),
                              if (_expanded) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    auth.user!.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: widget.child),
            ],
          ),
          if (_pendingInvite != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.75),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              strings.remoteSessionRequest,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            CircleAvatar(
                              radius: 34,
                              backgroundImage:
                                  _pendingInvite!.requesterAvatarUrl.isNotEmpty
                                  ? NetworkImage(
                                      _pendingInvite!.requesterAvatarUrl,
                                    )
                                  : null,
                              child: _pendingInvite!.requesterAvatarUrl.isEmpty
                                  ? Text(
                                      _pendingInvite!
                                          .requesterName
                                          .characters
                                          .first,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _pendingInvite!.requesterName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Expires in ${_inviteRemaining.inMinutes.toString().padLeft(2, '0')}:${(_inviteRemaining.inSeconds % 60).toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (_inviteActionError != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _inviteActionError!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _resolveInvite('reject'),
                                    child: Text(strings.decline),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => _resolveInvite('accept'),
                                    child: Text(strings.accept),
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
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.expanded,
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool expanded;
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? const Color(0xFF1F5D86) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              if (expanded) ...[
                const SizedBox(width: 12),
                Text(label, style: const TextStyle(color: Colors.white)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
