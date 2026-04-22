import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/state/app_strings.dart';
import '../app/state/appearance_controller.dart';
import '../app/state/auth_controller.dart';
import '../../app/state/data_providers.dart';
import '../app/state/realtime_controller.dart';
import 'remote_support_page.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Load notifications on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsControllerProvider.notifier).loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref.watch(localeProvider));
    final notificationsState = ref.watch(notificationsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.notificationsTitle),
        actions: [
          if (notificationsState.unreadCount > 0)
            TextButton.icon(
              onPressed: () {
                ref
                    .read(notificationsControllerProvider.notifier)
                    .markAllRead();
              },
              icon: const Icon(Icons.done_all),
              label: Text(strings.markAllRead),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(notificationsControllerProvider.notifier)
                .loadNotifications(),
          ),
        ],
      ),
      body: notificationsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : notificationsState.error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${strings.notificationErrorPrefix}${notificationsState.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(notificationsControllerProvider.notifier)
                        .loadNotifications(),
                    child: Text(strings.retryAction),
                  ),
                ],
              ),
            )
          : notificationsState.notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(strings.noNotifications),
                ],
              ),
            )
          : NotificationsList(notifications: notificationsState.notifications),
    );
  }
}

class NotificationsList extends ConsumerWidget {
  final List<AppNotification> notifications;

  const NotificationsList({Key? key, required this.notifications})
    : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(ref.watch(localeProvider));
    final currentUserId = ref.read(authControllerProvider).user?.id.toString() ?? '';

    Future<void> openRemoteSession({
      required String peerName,
      required String peerUserId,
      required String sessionToken,
      required bool sendLocalScreen,
    }) async {
      if (peerUserId.trim().isEmpty || sessionToken.trim().isEmpty) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => RemoteSupportPage(
            deviceName: peerName,
            deviceId: peerUserId,
            sendLocalScreen: sendLocalScreen,
            sessionId: sessionToken,
            currentUserId: currentUserId,
            signalingService: ref.read(signalingClientProvider),
            isDarkMode: Theme.of(context).brightness == Brightness.dark,
            translate: (value) => value,
          ),
        ),
      );
    }

    Future<String> requesterNameFor(String requesterId) async {
      try {
        final profile = await ref.read(apiClientProvider).get('/users/$requesterId');
        return (profile['display_name'] ?? profile['username'] ?? 'Remote host')
            .toString();
      } catch (_) {
        return 'Remote host';
      }
    }

    Future<String?> friendRequestIdForRequester(String requesterId) async {
      final requests = await ref
          .read(apiClientProvider)
          .get('/friends/requests');
      final incoming = ((requests['incoming'] as List?) ?? const []).map(
        (e) => Map<String, dynamic>.from((e as Map?) ?? const {}),
      );
      for (final req in incoming) {
        if ((req['requester_id'] ?? '').toString() == requesterId) {
          return (req['id'] ?? '').toString();
        }
      }
      return null;
    }

    Future<void> actOnNotification(
      AppNotification notification,
      String action,
    ) async {
      try {
        if (notification.type == 'friend_request') {
          final requesterId = (notification.payload['requester_id'] ?? '')
              .toString();
          final requestId = await friendRequestIdForRequester(requesterId);
          if (requestId != null && requestId.isNotEmpty) {
            await ref
                .read(apiClientProvider)
                .patch('/friends/request/$requestId', body: {'action': action});
          }
        } else if (notification.type == 'remote_session_request' ||
            notification.type == 'remote_invite') {
          final inviteId = (notification.payload['invite_id'] ?? '').toString();
          if (inviteId.isNotEmpty) {
            final response = await ref
                .read(apiClientProvider)
                .patch(
                  '/remote/invite/$inviteId',
                  body: {'action': action == 'accept' ? 'accept' : 'reject'},
                );
            if (action == 'accept') {
              final sessionToken = (response['session_token'] ?? '')
                  .toString()
                  .trim();
              final peerUserId = (response['target_user_id'] ?? '')
                  .toString()
                  .trim();
              final requesterId = (notification.payload['requester_id'] ?? '')
                  .toString()
                  .trim();
              if (sessionToken.isNotEmpty && peerUserId.isNotEmpty) {
                await openRemoteSession(
                  peerName: await requesterNameFor(requesterId),
                  peerUserId: peerUserId,
                  sessionToken: sessionToken,
                  sendLocalScreen: true,
                );
              }
            }
          }
        }
        await ref
            .read(notificationsControllerProvider.notifier)
            .markAsRead(notification.id);
        await ref
            .read(notificationsControllerProvider.notifier)
            .loadNotifications();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${strings.notificationActionFailedPrefix}$e')));
      }
    }

    return ListView.separated(
      itemCount: notifications.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: Colors.grey.shade200),
      itemBuilder: (context, index) {
        final notif = notifications[index];
        final actionable =
            notif.type == 'friend_request' ||
            notif.type == 'remote_session_request' ||
            notif.type == 'remote_invite';
        return NotificationTile(
          notification: notif,
          onTap: () {
            if (!notif.read) {
              ref
                  .read(notificationsControllerProvider.notifier)
                  .markAsRead(notif.id);
            }
            if (notif.actionUrl != null) {
              context.push(notif.actionUrl!);
            }
          },
          onAccept: actionable
              ? () async {
                  await actOnNotification(notif, 'accept');
                }
              : null,
          onDecline: actionable
              ? () async {
                  await actOnNotification(notif, 'reject');
                }
              : null,
        );
      },
    );
  }
}

class NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const NotificationTile({
    Key? key,
    required this.notification,
    required this.onTap,
    this.onAccept,
    this.onDecline,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(Localizations.localeOf(context));
    final icon = _getIconForType(notification.type);
    final color = _getColorForType(notification.type);

    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(icon, color: color),
          ),
          title: Text(notification.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _formatTime(notification.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          trailing: !notification.read
              ? Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(6),
                  ),
                )
              : null,
          onTap: onTap,
          enabled: !notification.read,
        ),
        if (onAccept != null || onDecline != null)
          Padding(
            padding: const EdgeInsets.only(left: 72, right: 16, bottom: 10),
            child: Row(
              children: [
                if (onDecline != null)
                  OutlinedButton(
                    onPressed: onDecline,
                    child: Text(strings.decline),
                  ),
                const SizedBox(width: 8),
                if (onAccept != null)
                  FilledButton(
                    onPressed: onAccept,
                    child: Text(strings.accept),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'friend_request':
        return Icons.person_add;
      case 'friend_accepted':
        return Icons.person_add_outlined;
      case 'message':
        return Icons.mail;
      case 'mention':
        return Icons.alternate_email;
      case 'remote_invite':
        return Icons.videocam;
      case 'community_message':
        return Icons.groups;
      case 'community_announcement':
        return Icons.campaign;
      default:
        return Icons.notifications;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'friend_request':
        return Colors.blue;
      case 'friend_accepted':
        return Colors.green;
      case 'message':
        return Colors.purple;
      case 'mention':
        return Colors.orange;
      case 'remote_invite':
        return Colors.red;
      case 'community_message':
        return Colors.teal;
      case 'community_announcement':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
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
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${time.month}/${time.day}';
    }
  }
}

// Notification badge widget for app bar
class NotificationBadge extends ConsumerWidget {
  const NotificationBadge({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsState = ref.watch(notificationsControllerProvider);

    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications),
          onPressed: () => context.push('/notifications'),
        ),
        if (notificationsState.unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                notificationsState.unreadCount > 99
                    ? '99+'
                    : notificationsState.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
