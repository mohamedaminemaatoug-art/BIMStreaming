import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../services/ws_client.dart';

// Initialize API Client - must call init() on app startup
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.dispose);
  return client;
});

// Initialize WebSocket Client
final wsClientProvider = Provider<WsClient>((ref) {
  final client = WsClient();
  ref.onDispose(client.dispose);
  return client;
});

// WebSocket events stream - connects automatically when user is logged in
final wsEventsProvider = StreamProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async* {
  final wsClient = ref.watch(wsClientProvider);
  final apiClient = ref.watch(apiClientProvider);
  final token = apiClient.accessToken;

  if (token == null) {
    // Not logged in, close stream
    return;
  }

  // Connect WebSocket if not already connected
  if (!wsClient.isConnected) {
    await wsClient.connect(token);
  }

  // Yield events from WebSocket
  yield* wsClient.events;
});

// ============== Friends Data ==============

class Friend {
  const Friend({
    required this.id,
    required this.name,
    required this.email,
    required this.avatar,
    required this.isOnline,
    required this.lastSeen,
    this.availability = 'offline',
    this.statusMessage = '',
    this.statusEmoji = '',
  });

  final String id;
  final String name;
  final String email;
  final String avatar;
  final bool isOnline;
  final DateTime? lastSeen;
  final String availability;
  final String statusMessage;
  final String statusEmoji;

  Friend copyWith({
    String? id,
    String? name,
    String? email,
    String? avatar,
    bool? isOnline,
    DateTime? lastSeen,
    String? availability,
    String? statusMessage,
    String? statusEmoji,
  }) {
    return Friend(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      availability: availability ?? this.availability,
      statusMessage: statusMessage ?? this.statusMessage,
      statusEmoji: statusEmoji ?? this.statusEmoji,
    );
  }
}

class FriendsState {
  const FriendsState({
    this.friends = const [],
    this.pending = const [],
    this.blocked = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Friend> friends;
  final List<Friend> pending;
  final List<Friend> blocked;
  final bool isLoading;
  final String? error;

  FriendsState copyWith({
    List<Friend>? friends,
    List<Friend>? pending,
    List<Friend>? blocked,
    bool? isLoading,
    String? error,
  }) {
    return FriendsState(
      friends: friends ?? this.friends,
      pending: pending ?? this.pending,
      blocked: blocked ?? this.blocked,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class FriendsController extends StateNotifier<FriendsState> {
  FriendsController(this._apiClient) : super(const FriendsState());

  final ApiClient _apiClient;

  String _nullableString(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is Map) {
      final valid = value['Valid'];
      if (valid == false) {
        return '';
      }
      final inner = value['String'];
      if (inner != null) {
        return inner.toString().trim();
      }
      return '';
    }
    return value.toString().trim();
  }

  Friend _friendFromUserMap(Map<String, dynamic> user) {
    final displayName = _nullableString(user['display_name']);
    final username = _nullableString(user['username']);
    final email = _nullableString(user['email']);
    final isOnline = (user['is_online'] as bool?) ?? false;
    return Friend(
      id: (user['id'] ?? '').toString(),
      name: displayName.isNotEmpty
          ? displayName
          : (username.isNotEmpty ? username : (email.isNotEmpty ? email : '-')),
      email: email,
      avatar: _nullableString(user['avatar_url']),
      isOnline: isOnline,
      lastSeen: DateTime.tryParse(
        _nullableString(user['last_seen_at']),
      ),
    );
  }

  String _normalizeAvailability(String value, {required bool fallbackOnline}) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'away' || normalized == 'busy' || normalized == 'offline') {
      return normalized;
    }
    return fallbackOnline ? 'online' : 'offline';
  }

  Future<void> loadFriends() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final friendsData = await _apiClient.get('/friends');
      final requestsData = await _apiClient.get('/friends/requests');
      final blockedData = await _apiClient.get('/friends/blocked');

      final friends = ((friendsData['data'] as List?) ?? const [])
          .map(
            (f) => _friendFromUserMap(
              Map<String, dynamic>.from((f as Map?) ?? const {}),
            ),
          )
          .toList();

      final statuses = <String, Map<String, dynamic>>{};
      await Future.wait(
        friends.map((friend) async {
          if (friend.id.isEmpty) {
            return;
          }
          try {
            final response = await _apiClient.get('/users/${friend.id}/status');
            final status = response['status'];
            if (status is Map) {
              statuses[friend.id] = Map<String, dynamic>.from(status);
            }
          } catch (_) {}
        }),
      );

      final enrichedFriends = friends.map((friend) {
        final status = statuses[friend.id];
        if (status == null) {
          return friend.copyWith(
            availability: friend.isOnline ? 'online' : 'offline',
          );
        }
        return friend.copyWith(
          availability: _normalizeAvailability(
            (status['availability'] ?? '').toString(),
            fallbackOnline: friend.isOnline,
          ),
          statusMessage: _nullableString(status['message']),
          statusEmoji: _nullableString(status['emoji']),
        );
      }).toList();

      final incoming = ((requestsData['incoming'] as List?) ?? const [])
          .map((f) => Map<String, dynamic>.from((f as Map?) ?? const {}))
          .toList();

      final pending = <Friend>[];
      for (final req in incoming) {
        final requesterId = (req['requester_id'] ?? '').toString();
        if (requesterId.isEmpty) {
          continue;
        }
        try {
          final profile = await _apiClient.get('/users/$requesterId');
          pending.add(
            Friend(
              id: (req['id'] ?? requesterId).toString(),
              name: _nullableString(profile['display_name']).isNotEmpty
                  ? _nullableString(profile['display_name'])
                  : (_nullableString(profile['username']).isNotEmpty
                        ? _nullableString(profile['username'])
                        : 'User $requesterId'),
              email: _nullableString(profile['email']),
              avatar: _nullableString(profile['avatar_url']),
              isOnline: (profile['is_online'] as bool?) ?? false,
              lastSeen: null,
            ),
          );
        } catch (_) {
          pending.add(
            Friend(
              id: (req['id'] ?? requesterId).toString(),
              name: 'User $requesterId',
              email: '',
              avatar: '',
              isOnline: false,
              lastSeen: null,
            ),
          );
        }
      }

      final blocked = ((blockedData['data'] as List?) ?? const [])
          .map(
            (f) => _friendFromUserMap(
              Map<String, dynamic>.from((f as Map?) ?? const {}),
            ),
          )
          .toList();

      state = state.copyWith(
        friends: enrichedFriends,
        pending: pending,
        blocked: blocked,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> sendFriendRequest(String userId) async {
    try {
      await _apiClient.post('/friends/request/$userId');
      await loadFriends();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> sendRemoteSessionInvite(String userId) async {
    try {
      await _apiClient.post('/remote/invite/$userId');
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> acceptFriendRequest(String userId) async {
    try {
      await _apiClient.patch(
        '/friends/request/$userId',
        body: {'action': 'accept'},
      );
      await loadFriends();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> declineFriendRequest(String userId) async {
    try {
      await _apiClient.patch(
        '/friends/request/$userId',
        body: {'action': 'reject'},
      );
      await loadFriends();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> removeFriend(String userId) async {
    try {
      await _apiClient.delete('/friends/$userId');
      await loadFriends();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> blockUser(String userId) async {
    try {
      await _apiClient.post('/friends/block/$userId');
      await loadFriends();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> unblockUser(String userId) async {
    try {
      await _apiClient.delete('/friends/block/$userId');
      await loadFriends();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<List<Friend>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const <Friend>[];
    }
    final data = await _apiClient.get(
      '/users/search?q=${Uri.encodeQueryComponent(q)}',
    );
    return ((data['data'] as List?) ?? const [])
        .map(
          (u) => _friendFromUserMap(
            Map<String, dynamic>.from((u as Map?) ?? const {}),
          ),
        )
        .toList();
  }

  void updateFriendOnlineStatus(String userId, bool isOnline) {
    final updatedFriends = state.friends.map((f) {
      if (f.id == userId) {
        return f.copyWith(
          isOnline: isOnline,
          availability: isOnline ? 'online' : 'offline',
          lastSeen: DateTime.now(),
        );
      }
      return f;
    }).toList();
    state = state.copyWith(friends: updatedFriends);
  }
}

final friendsControllerProvider =
    StateNotifierProvider<FriendsController, FriendsState>((ref) {
      final apiClient = ref.watch(apiClientProvider);
      return FriendsController(apiClient);
    });

// ============== Messages Data ==============

class DMMessage {
  const DMMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.sentAt,
    this.editedAt,
    this.reactions = const <String, int>{},
    this.readBy = const <String>{},
    this.replyTo,
    this.attachments = const [],
    this.isRead = false,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String body;
  final DateTime sentAt;
  final DateTime? editedAt;
  final Map<String, int> reactions;
  final Set<String> readBy;
  final String? replyTo;
  final List<String> attachments;
  final bool isRead;

  DMMessage copyWith({
    Map<String, int>? reactions,
    Set<String>? readBy,
    String? body,
    DateTime? editedAt,
  }) {
    return DMMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      body: body ?? this.body,
      sentAt: sentAt,
      editedAt: editedAt ?? this.editedAt,
      reactions: reactions ?? this.reactions,
      readBy: readBy ?? this.readBy,
      replyTo: replyTo,
      attachments: attachments,
      isRead: isRead,
    );
  }
}

class DMConversation {
  const DMConversation({
    required this.userId,
    required this.userName,
    required this.avatar,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.isTyping,
  });

  final String userId;
  final String userName;
  final String avatar;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isTyping;
}

class MessagesState {
  const MessagesState({
    this.conversations = const [],
    this.messagesByUserId = const {},
    this.typingByUserId = const {},
    this.isLoadingConversations = false,
    this.currentUserId,
    this.error,
  });

  final List<DMConversation> conversations;
  final Map<String, List<DMMessage>> messagesByUserId;
  final Map<String, bool> typingByUserId;
  final bool isLoadingConversations;
  final String? currentUserId;
  final String? error;

  MessagesState copyWith({
    List<DMConversation>? conversations,
    Map<String, List<DMMessage>>? messagesByUserId,
    Map<String, bool>? typingByUserId,
    bool? isLoadingConversations,
    String? currentUserId,
    String? error,
  }) {
    return MessagesState(
      conversations: conversations ?? this.conversations,
      messagesByUserId: messagesByUserId ?? this.messagesByUserId,
      typingByUserId: typingByUserId ?? this.typingByUserId,
      isLoadingConversations:
          isLoadingConversations ?? this.isLoadingConversations,
      currentUserId: currentUserId ?? this.currentUserId,
      error: error ?? this.error,
    );
  }
}

class MessagesController extends StateNotifier<MessagesState> {
  MessagesController(this._apiClient) : super(const MessagesState());

  final ApiClient _apiClient;

  Future<void> loadConversations() async {
    state = state.copyWith(isLoadingConversations: true, error: null);
    try {
      final data = await _apiClient.get('/dm');
      final rawConversations = ((data['data'] as List?) ?? const [])
          .map((raw) => Map<String, dynamic>.from((raw as Map?) ?? const {}))
          .map(
            (c) => DMConversation(
              userId: (c['contact_id'] ?? c['user_id'] ?? '').toString(),
              userName:
                  (c['contact_name'] ??
                          c['user_name'] ??
                          c['contact_id'] ??
                          'User')
                      .toString(),
              avatar: (c['avatar_url'] ?? c['avatar'] ?? '').toString(),
              lastMessage: (c['last_message'] ?? '').toString(),
              lastMessageTime:
                  DateTime.tryParse(
                    (c['last_message_at'] ?? c['last_message_time'] ?? '')
                        .toString(),
                  ) ??
                  DateTime.now(),
              unreadCount: (c['unread_count'] as num?)?.toInt() ?? 0,
              isTyping: false,
            ),
          )
          .toList();

      final profileCache = <String, Map<String, dynamic>>{};
      final conversations = <DMConversation>[];
      for (final conversation in rawConversations) {
        var nextName = conversation.userName;
        var nextAvatar = conversation.avatar;
        final looksLikeId =
            nextName == conversation.userId ||
            nextName.trim().isEmpty ||
            nextName.startsWith('User ');
        if (looksLikeId && conversation.userId.trim().isNotEmpty) {
          profileCache[conversation.userId] ??=
              await _apiClient.get('/users/${conversation.userId}');
          final profile = profileCache[conversation.userId] ?? const {};
          final displayName = (profile['display_name'] ?? '').toString().trim();
          final username = (profile['username'] ?? '').toString().trim();
          final avatarUrl = (profile['avatar_url'] ?? '').toString().trim();
          if (displayName.isNotEmpty) {
            nextName = displayName;
          } else if (username.isNotEmpty) {
            nextName = username;
          }
          if (avatarUrl.isNotEmpty) {
            nextAvatar = avatarUrl;
          }
        }

        conversations.add(
          DMConversation(
            userId: conversation.userId,
            userName: nextName,
            avatar: nextAvatar,
            lastMessage: conversation.lastMessage,
            lastMessageTime: conversation.lastMessageTime,
            unreadCount: conversation.unreadCount,
            isTyping: conversation.isTyping,
          ),
        );
      }

      state = state.copyWith(
        conversations: conversations,
        isLoadingConversations: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingConversations: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMessages(String userId) async {
    try {
      final data = await _apiClient.get('/dm/$userId');
      final messages =
          ((data['data'] as List?) ?? const [])
              .map(
                (raw) => Map<String, dynamic>.from((raw as Map?) ?? const {}),
              )
              .map(
                (m) => DMMessage(
                  id: (m['id'] ?? '').toString(),
                  conversationId: userId,
                  senderId: (m['sender_id'] ?? '').toString(),
                  senderName: (m['sender_name'] ?? m['sender_id'] ?? '')
                      .toString(),
                  body: (m['content'] ?? m['body'] ?? '').toString(),
                  sentAt:
                      DateTime.tryParse(
                        (m['created_at'] ?? m['sent_at'] ?? '').toString(),
                      ) ??
                      DateTime.now(),
                  editedAt: DateTime.tryParse(
                    (m['edited_at'] ?? '').toString(),
                  ),
                  reactions: const <String, int>{},
                  readBy: ((m['is_read'] as bool?) ?? false)
                      ? <String>{(m['recipient_id'] ?? '').toString()}
                      : const <String>{},
                  replyTo: (m['reply_to'] ?? m['reply_to_id'])?.toString(),
                  attachments: const <String>[],
                  isRead: (m['is_read'] as bool?) ?? false,
                ),
              )
              .toList()
            ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      final updated = Map.of(state.messagesByUserId);
      updated[userId] = messages;
      state = state.copyWith(messagesByUserId: updated);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> sendMessage(String userId, String body) async {
    try {
      await _apiClient.post('/dm/$userId', body: {'content': body});
      await loadMessages(userId);
      await loadConversations();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markConversationRead(String userId) async {
    try {
      await _apiClient.patch('/dm/$userId/read');
      final updated = Map<String, List<DMMessage>>.from(state.messagesByUserId);
      updated[userId] = (updated[userId] ?? const <DMMessage>[])
          .map((m) => m.copyWith(readBy: {...m.readBy, userId}))
          .toList();
      state = state.copyWith(messagesByUserId: updated);
      await loadConversations();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> editMessage(String userId, String messageId, String body) async {
    try {
      await _apiClient.patch(
        '/dm/$userId/message/$messageId',
        body: {'body': body},
      );
      await loadMessages(userId);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteMessage(String userId, String messageId) async {
    try {
      await _apiClient.delete('/dm/$userId/message/$messageId');
      await loadMessages(userId);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void setTypingStatus(String userId, bool isTyping) {
    final updated = Map.of(state.typingByUserId);
    updated[userId] = isTyping;
    state = state.copyWith(typingByUserId: updated);
  }

  void addMessage(String userId, DMMessage message) {
    final updated = Map.of(state.messagesByUserId);
    if (updated[userId] == null) {
      updated[userId] = [];
    }
    updated[userId] = [...updated[userId]!, message];
    state = state.copyWith(messagesByUserId: updated);
  }
}

final messagesControllerProvider =
    StateNotifierProvider<MessagesController, MessagesState>((ref) {
      final apiClient = ref.watch(apiClientProvider);
      return MessagesController(apiClient);
    });

// ============== Communities Data ==============

class Community {
  const Community({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.memberCount,
    this.isMember = false,
    this.code = '',
  });

  final String id;
  final String name;
  final String description;
  final String icon;
  final int memberCount;
  final bool isMember;
  final String code;
}

class CommunitiesState {
  const CommunitiesState({
    this.communities = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Community> communities;
  final bool isLoading;
  final String? error;

  CommunitiesState copyWith({
    List<Community>? communities,
    bool? isLoading,
    String? error,
  }) {
    return CommunitiesState(
      communities: communities ?? this.communities,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class CommunitiesController extends StateNotifier<CommunitiesState> {
  CommunitiesController(this._apiClient) : super(const CommunitiesState());

  final ApiClient _apiClient;

  Future<void> loadCommunities() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _apiClient.get('/communities');
      final communities = ((data['data'] as List?) ?? const [])
          .map((raw) => Map<String, dynamic>.from((raw as Map?) ?? const {}))
          .map(
            (c) => Community(
              id: (c['id'] ?? '').toString(),
              name: (c['name'] ?? '').toString(),
              description:
                  (c['description']?['String'] ?? c['description'] ?? '')
                      .toString(),
              icon: (c['icon'] ?? '🏢').toString(),
              memberCount: (c['member_count'] as num?)?.toInt() ?? 0,
              isMember: (c['is_member'] as bool?) ?? true,
              code: (c['code'] ?? '').toString(),
            ),
          )
          .toList();
      state = state.copyWith(communities: communities, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> joinCommunity(String communityIdOrCode) async {
    try {
      await _apiClient.post(
        '/communities/join',
        body: {
          'code': communityIdOrCode,
          'community_id': communityIdOrCode,
        },
      );
      await loadCommunities();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> leaveCommunity(String communityId) async {
    try {
      await _apiClient.post('/communities/$communityId/leave');
      await loadCommunities();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<Map<String, dynamic>> createCommunity({
    required String name,
    required String description,
    required bool isPublic,
  }) {
    return _apiClient.post(
      '/communities',
      body: {
        'name': name,
        'description': description,
        'is_public': isPublic,
      },
    );
  }

  Future<Map<String, dynamic>> loadCommunityDetails(String communityId) {
    return _apiClient.get('/communities/$communityId');
  }

  Future<List<Map<String, dynamic>>> loadCommunityMembers(
    String communityId,
  ) async {
    final data = await _apiClient.get('/communities/$communityId/members');
    return ((data['data'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from((e as Map?) ?? const {}))
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadCommunityMessages(
    String communityId,
  ) async {
    final data = await _apiClient.get('/communities/$communityId/messages');
    return ((data['data'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from((e as Map?) ?? const {}))
        .toList();
  }

  Future<void> sendCommunityMessage(String communityId, String content) async {
    await _apiClient.post(
      '/communities/$communityId/messages',
      body: {'content': content},
    );
  }

  Future<void> joinByCode(String code) async {
    await joinCommunity(code);
    await loadCommunities();
  }

  Future<void> updateCommunityMember({
    required String communityId,
    required String userId,
    required String role,
    String? departmentId,
  }) async {
    await _apiClient.patch(
      '/communities/$communityId/members/$userId',
      body: {
        'role': role,
        'department_id': departmentId ?? '',
      },
    );
  }

  Future<void> removeCommunityMember({
    required String communityId,
    required String userId,
  }) async {
    await _apiClient.delete('/communities/$communityId/members/$userId');
  }

  Future<Map<String, dynamic>> createCommunityDepartment({
    required String communityId,
    required String name,
  }) {
    return _apiClient.post(
      '/communities/$communityId/departments',
      body: {'name': name},
    );
  }

  Future<Map<String, dynamic>> updateCommunityDepartment({
    required String communityId,
    required String departmentId,
    required String name,
  }) {
    return _apiClient.patch(
      '/communities/$communityId/departments/$departmentId',
      body: {'name': name},
    );
  }

  Future<void> deleteCommunityDepartment({
    required String communityId,
    required String departmentId,
  }) async {
    await _apiClient.delete('/communities/$communityId/departments/$departmentId');
  }

  Future<Map<String, dynamic>> generateCommunityInvite(String communityId) {
    return _apiClient.post('/communities/$communityId/invite');
  }

  Future<void> addCommunityMemberByEmail({
    required String communityId,
    required String email,
  }) async {
    await _apiClient.post(
      '/communities/$communityId/members',
      body: {'email': email, 'role': 'user'},
    );
  }
}

final communitiesControllerProvider =
    StateNotifierProvider<CommunitiesController, CommunitiesState>((ref) {
      final apiClient = ref.watch(apiClientProvider);
      return CommunitiesController(apiClient);
    });

// ============== Notifications Data ==============

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.read = false,
    this.actionUrl,
    this.payload = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final String message;
  final String type; // friend_request, message, mention, etc.
  final DateTime createdAt;
  final bool read;
  final String? actionUrl;
  final Map<String, dynamic> payload;
}

class NotificationsState {
  const NotificationsState({
    this.notifications = const [],
    this.isLoading = false,
    this.unreadCount = 0,
    this.error,
  });

  final List<AppNotification> notifications;
  final bool isLoading;
  final int unreadCount;
  final String? error;

  NotificationsState copyWith({
    List<AppNotification>? notifications,
    bool? isLoading,
    int? unreadCount,
    String? error,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      unreadCount: unreadCount ?? this.unreadCount,
      error: error ?? this.error,
    );
  }
}

class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._apiClient) : super(const NotificationsState());

  final ApiClient _apiClient;

  Map<String, dynamic> _parsePayload(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = utf8.decode(base64Decode(raw));
        final json = jsonDecode(decoded);
        if (json is Map) {
          return Map<String, dynamic>.from(json);
        }
      } catch (_) {
        // Keep empty payload when decode fails.
      }
    }
    return const <String, dynamic>{};
  }

  Future<void> loadNotifications() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _apiClient.get('/notifications');
      final notifications = ((data['data'] as List?) ?? const [])
          .map((raw) => Map<String, dynamic>.from((raw as Map?) ?? const {}))
          .map(
            (n) => AppNotification(
              id: (n['id'] ?? '').toString(),
              title: (n['type'] ?? 'Notification').toString(),
              message: (n['type'] ?? 'New activity').toString(),
              type: (n['type'] ?? 'general').toString(),
              createdAt:
                  DateTime.tryParse((n['created_at'] ?? '').toString()) ??
                  DateTime.now(),
              read: (n['is_read'] as bool?) ?? false,
              actionUrl: null,
              payload: _parsePayload(n['payload']),
            ),
          )
          .toList();
      final unread =
          (data['unread_count'] as num?)?.toInt() ??
          notifications.where((n) => !n.read).length;
      state = state.copyWith(
        notifications: notifications,
        unreadCount: unread,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _apiClient.patch('/notifications/$notificationId/read');
      await loadNotifications();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markAllRead() async {
    try {
      await _apiClient.patch('/notifications/read');
      await loadNotifications();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void addNotification(AppNotification notification) {
    final updated = [notification, ...state.notifications];
    state = state.copyWith(
      notifications: updated,
      unreadCount: state.unreadCount + 1,
    );
  }
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
      final apiClient = ref.watch(apiClientProvider);
      return NotificationsController(apiClient);
    });

// ============== Remote Sessions Data ==============

class RemoteSession {
  const RemoteSession({
    required this.id,
    required this.deviceId,
    required this.partnerName,
    required this.sessionCode,
    required this.startedAt,
    required this.status, // active, ended
    this.duration,
  });

  final String id;
  final String deviceId;
  final String partnerName;
  final String sessionCode;
  final DateTime startedAt;
  final String status;
  final Duration? duration;
}

class RemoteSessionsState {
  const RemoteSessionsState({
    this.sessions = const [],
    this.deviceId,
    this.devicePassword,
    this.isLoading = false,
    this.error,
  });

  final List<RemoteSession> sessions;
  final String? deviceId;
  final String? devicePassword;
  final bool isLoading;
  final String? error;

  RemoteSessionsState copyWith({
    List<RemoteSession>? sessions,
    String? deviceId,
    String? devicePassword,
    bool? isLoading,
    String? error,
  }) {
    return RemoteSessionsState(
      sessions: sessions ?? this.sessions,
      deviceId: deviceId ?? this.deviceId,
      devicePassword: devicePassword ?? this.devicePassword,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class RemoteSessionsController extends StateNotifier<RemoteSessionsState> {
  RemoteSessionsController(this._apiClient)
    : super(const RemoteSessionsState());

  final ApiClient _apiClient;

  Future<void> loadSessions() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _apiClient.get('/remote/history');
      final sessions =
          (data['sessions'] as List?)
              ?.map(
                (s) => RemoteSession(
                  id: s['id'] as String,
                  deviceId: s['device_id'] as String,
                  partnerName: s['partner_name'] as String,
                  sessionCode: s['session_code'] as String,
                  startedAt: DateTime.parse(s['started_at'] as String),
                  status: s['status'] as String,
                  duration: s['duration'] != null
                      ? Duration(seconds: s['duration'] as int)
                      : null,
                ),
              )
              .toList() ??
          [];
      state = state.copyWith(
        sessions: sessions,
        deviceId: data['device_id'] as String?,
        devicePassword: data['device_password'] as String?,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final remoteSessionsControllerProvider =
    StateNotifierProvider<RemoteSessionsController, RemoteSessionsState>((ref) {
      final apiClient = ref.watch(apiClientProvider);
      return RemoteSessionsController(apiClient);
    });

// ============== WebSocket Provider ==============

class WSMessage {
  final String type;
  final Map<String, dynamic> data;

  WSMessage({required this.type, required this.data});

  factory WSMessage.fromJson(Map<String, dynamic> json) {
    final rawData =
        (json['data'] as Map?) ?? (json['payload'] as Map?) ?? const {};
    return WSMessage(
      type: json['type'] as String,
      data: Map<String, dynamic>.from(rawData),
    );
  }
}

final wsProvider = StreamProvider.autoDispose<WSMessage>((ref) async* {
  final wsClient = ref.watch(wsClientProvider);
  final apiClient = ref.watch(apiClientProvider);
  final token = apiClient.accessToken;

  if (token == null) {
    return;
  }

  if (!wsClient.isConnected) {
    await wsClient.connect(token);
  }

  await for (final event in wsClient.events) {
    yield WSMessage.fromJson(event);
  }
});
