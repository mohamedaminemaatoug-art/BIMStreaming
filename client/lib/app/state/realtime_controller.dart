import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/signaling_client_service.dart';
import 'data_providers.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.reactions = const <String, int>{},
    this.readBy = const <String>{},
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final Map<String, int> reactions;
  final Set<String> readBy;

  ChatMessage copyWith({Map<String, int>? reactions, Set<String>? readBy}) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      body: body,
      createdAt: createdAt,
      reactions: reactions ?? this.reactions,
      readBy: readBy ?? this.readBy,
    );
  }
}

class RealtimeState {
  const RealtimeState({
    this.messagesByConversation = const <String, List<ChatMessage>>{},
    this.typingByConversation = const <String, Set<String>>{},
  });

  final Map<String, List<ChatMessage>> messagesByConversation;
  final Map<String, Set<String>> typingByConversation;

  RealtimeState copyWith({
    Map<String, List<ChatMessage>>? messagesByConversation,
    Map<String, Set<String>>? typingByConversation,
  }) {
    return RealtimeState(
      messagesByConversation:
          messagesByConversation ?? this.messagesByConversation,
      typingByConversation: typingByConversation ?? this.typingByConversation,
    );
  }
}

class RealtimeController extends StateNotifier<RealtimeState> {
  RealtimeController(this.ref) : super(const RealtimeState()) {
    setupWSHandlers();
  }

  final Ref ref;

  void setupWSHandlers() {
    ref.listen<AsyncValue<WSMessage>>(wsProvider, (previous, next) {
      next.whenData(_handleWSMessage);
    });
  }

  void _handleWSMessage(WSMessage message) {
    switch (message.type) {
      case 'dm:new':
        final conversationId =
            (message.data['conversation_id'] ?? message.data['from_user_id'])
                ?.toString();
        final senderId = message.data['sender_id']?.toString();
        final body = (message.data['content'] ?? message.data['body'])
            ?.toString();
        if (conversationId == null || senderId == null || body == null) {
          return;
        }
        ref
            .read(messagesControllerProvider.notifier)
            .addMessage(
              conversationId,
              DMMessage(
                id:
                    (message.data['id'] ??
                            DateTime.now().millisecondsSinceEpoch)
                        .toString(),
                conversationId: conversationId,
                senderId: senderId,
                senderName: senderId,
                body: body,
                sentAt:
                    DateTime.tryParse(
                      (message.data['created_at'] ?? '').toString(),
                    ) ??
                    DateTime.now(),
                isRead: false,
              ),
            );
        _appendMessage(
          conversationId,
          ChatMessage(
            id: (message.data['id'] ?? DateTime.now().millisecondsSinceEpoch)
                .toString(),
            conversationId: conversationId,
            senderId: senderId,
            body: body,
            createdAt: DateTime.now(),
          ),
        );
        break;
      case 'dm:typing':
        final conversationId =
            (message.data['conversation_id'] ?? message.data['from_user_id'])
                ?.toString();
        final userId = message.data['from_user_id']?.toString();
        if (conversationId != null && userId != null) {
          ref
              .read(messagesControllerProvider.notifier)
              .setTypingStatus(conversationId, true);
          setTyping(
            conversationId: conversationId,
            userId: userId,
            typing: true,
          );
        }
        break;
      case 'dm:typing_stop':
        final conversationId =
            (message.data['conversation_id'] ?? message.data['from_user_id'])
                ?.toString();
        final userId = message.data['from_user_id']?.toString();
        if (conversationId != null && userId != null) {
          ref
              .read(messagesControllerProvider.notifier)
              .setTypingStatus(conversationId, false);
          setTyping(
            conversationId: conversationId,
            userId: userId,
            typing: false,
          );
        }
        break;
      case 'notification:new':
        final notification = AppNotification(
          id: (message.data['id'] ?? DateTime.now().millisecondsSinceEpoch)
              .toString(),
          title: message.data['title']?.toString() ?? 'Notification',
          message: message.data['message']?.toString() ?? '',
          type: message.data['type']?.toString() ?? 'general',
          createdAt: DateTime.now(),
        );
        ref
            .read(notificationsControllerProvider.notifier)
            .addNotification(notification);
        break;
    }
  }

  void _appendMessage(String conversationId, ChatMessage message) {
    final next = Map<String, List<ChatMessage>>.from(
      state.messagesByConversation,
    );
    final list = List<ChatMessage>.from(next[conversationId] ?? const []);
    list.add(message);
    next[conversationId] = list;
    state = state.copyWith(messagesByConversation: next);
  }

  void sendMessage({
    required String conversationId,
    required String senderId,
    required String body,
  }) {
    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: conversationId,
      senderId: senderId,
      body: body,
      createdAt: DateTime.now(),
    );
    _appendMessage(conversationId, message);
    ref
        .read(messagesControllerProvider.notifier)
        .sendMessage(conversationId, body);
  }

  void setTyping({
    required String conversationId,
    required String userId,
    required bool typing,
  }) {
    final next = Map<String, Set<String>>.from(state.typingByConversation);
    final typers = Set<String>.from(next[conversationId] ?? const <String>{});
    if (typing) {
      typers.add(userId);
    } else {
      typers.remove(userId);
    }
    next[conversationId] = typers;
    state = state.copyWith(typingByConversation: next);
  }

  void addReaction({
    required String conversationId,
    required String messageId,
    required String reaction,
  }) {
    final messages = List<ChatMessage>.from(
      state.messagesByConversation[conversationId] ?? const <ChatMessage>[],
    );
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) {
      return;
    }

    final current = messages[idx];
    final updatedReactions = Map<String, int>.from(current.reactions);
    updatedReactions[reaction] = (updatedReactions[reaction] ?? 0) + 1;
    messages[idx] = current.copyWith(reactions: updatedReactions);

    final all = Map<String, List<ChatMessage>>.from(
      state.messagesByConversation,
    );
    all[conversationId] = messages;
    state = state.copyWith(messagesByConversation: all);
  }

  void markConversationRead({
    required String conversationId,
    required String userId,
  }) {
    final messages = List<ChatMessage>.from(
      state.messagesByConversation[conversationId] ?? const <ChatMessage>[],
    );
    final updated = messages
        .map((m) => m.copyWith(readBy: {...m.readBy, userId}))
        .toList();
    final all = Map<String, List<ChatMessage>>.from(
      state.messagesByConversation,
    );
    all[conversationId] = updated;
    state = state.copyWith(messagesByConversation: all);
    ref.read(messagesControllerProvider.notifier).loadMessages(conversationId);
  }

  void markAllNotificationsRead() {
    final notifications = ref
        .read(notificationsControllerProvider)
        .notifications;
    for (final n in notifications.where((n) => !n.read)) {
      ref.read(notificationsControllerProvider.notifier).markAsRead(n.id);
    }
  }
}

final signalingClientProvider = Provider<SignalingClientService>((ref) {
  return SignalingClientService();
});

final realtimeControllerProvider =
    StateNotifierProvider<RealtimeController, RealtimeState>((ref) {
      return RealtimeController(ref);
    });
