import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/state/app_strings.dart';
import '../app/state/appearance_controller.dart';
import '../../app/state/auth_controller.dart';
import '../../app/state/data_providers.dart';

class DMScreen extends ConsumerStatefulWidget {
  const DMScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DMScreen> createState() => _DMScreenState();
}

class _DMScreenState extends ConsumerState<DMScreen> {
  @override
  void initState() {
    super.initState();
    // Load conversations on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(messagesControllerProvider.notifier).loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesState = ref.watch(messagesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(messagesControllerProvider.notifier)
                .loadConversations(),
          ),
        ],
      ),
      body: messagesState.isLoadingConversations
          ? const Center(child: CircularProgressIndicator())
          : messagesState.error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Unable to load messages right now.'),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      messagesState.error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(messagesControllerProvider.notifier)
                        .loadConversations(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : messagesState.conversations.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mail_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No conversations yet'),
                  const SizedBox(height: 8),
                  Text(
                    'Start a conversation with a friend',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : ConversationsList(conversations: messagesState.conversations),
    );
  }
}

class ConversationsList extends ConsumerWidget {
  final List<DMConversation> conversations;

  const ConversationsList({Key? key, required this.conversations})
    : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
        return ListTile(
          leading: CircleAvatar(
            child: conv.avatar.isNotEmpty
                ? Image.network(conv.avatar, fit: BoxFit.cover)
                : Text(conv.userName[0].toUpperCase()),
          ),
          title: Text(conv.userName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conv.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (conv.isTyping)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: TypingIndicator(),
                ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTime(conv.lastMessageTime),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (conv.unreadCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      conv.unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onTap: () => context.push('/app/messages/${conv.userId}'),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d';
    } else {
      return '${time.month}/${time.day}';
    }
  }
}

class DMConversationScreen extends ConsumerStatefulWidget {
  final String userId;

  const DMConversationScreen({Key? key, required this.userId})
    : super(key: key);

  @override
  ConsumerState<DMConversationScreen> createState() =>
      _DMConversationScreenState();
}

class _DMConversationScreenState extends ConsumerState<DMConversationScreen> {
  late TextEditingController _messageController;
  late Future<Map<String, dynamic>?> _peerProfileFuture;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _peerProfileFuture = _loadPeerProfile();
    // Load messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(messagesControllerProvider.notifier).loadMessages(widget.userId);
    });
  }

  Future<Map<String, dynamic>?> _loadPeerProfile() async {
    try {
      final profile = await ref.read(apiClientProvider).get('/users/${widget.userId}');
      return Map<String, dynamic>.from((profile as Map?) ?? const {});
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final messagesState = ref.watch(messagesControllerProvider);
    final messages = messagesState.messagesByUserId[widget.userId] ?? [];
    final currentUserId = auth.user?.id ?? '';
    final strings = AppStrings.of(ref.watch(localeProvider));

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Map<String, dynamic>?> (
          future: _peerProfileFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final name = (profile?['display_name'] ?? profile?['username'] ?? widget.userId)
                .toString();
            return Text(name);
          },
        ),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.message_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(strings.noUsersFound),
                        const SizedBox(height: 8),
                        Text(
                          'Start chatting with this friend',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      return MessageBubble(
                        message: message,
                        isOwn: message.senderId == currentUserId,
                      );
                    },
                  ),
          ),
          if (messagesState.typingByUserId[widget.userId] ?? false)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: TypingIndicator(),
            ),
          MessageInputField(
            controller: _messageController,
            onTypingChanged: (typing) {
              ref.read(wsClientProvider).send({
                'type': typing ? 'dm:typing' : 'dm:typing_stop',
                'data': {
                  'conversation_id': widget.userId,
                  'from_user_id': currentUserId,
                },
              });
            },
            onSend: () {
              if (_messageController.text.isNotEmpty) {
                ref
                    .read(messagesControllerProvider.notifier)
                    .sendMessage(widget.userId, _messageController.text);
                ref
                    .read(messagesControllerProvider.notifier)
                    .markConversationRead(widget.userId);
                _messageController.clear();
              }
            },
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final DMMessage message;
  final bool isOwn;

  const MessageBubble({Key? key, required this.message, required this.isOwn})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Align(
        alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isOwn
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isOwn ? Colors.blue : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.body,
                    style: TextStyle(
                      color: isOwn ? Colors.white : Colors.black,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.sentAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isOwn
                              ? Colors.grey.shade200
                              : Colors.grey.shade600,
                        ),
                      ),
                      if (isOwn) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.isRead ? Icons.done_all : Icons.done,
                          size: 12,
                          color: Colors.grey.shade200,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (message.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  message.reactions.entries
                      .map((e) => '${e.key}${e.value > 1 ? e.value : ''}')
                      .join(' '),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class MessageInputField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<bool>? onTypingChanged;

  const MessageInputField({
    Key? key,
    required this.controller,
    required this.onSend,
    this.onTypingChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (value) =>
                  onTypingChanged?.call(value.trim().isNotEmpty),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            onPressed: onSend,
            child: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({Key? key}) : super(key: key);

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (index) => AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final offset =
                sin(
                  ((_controller.value * 2 * 3.14159) + (index * 3.14159 / 1.5)),
                ) *
                4;
            return Transform.translate(
              offset: Offset(0, offset),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
