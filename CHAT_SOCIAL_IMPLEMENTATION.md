# Chat & Social Features Implementation Guide

## Overview

This document describes the complete implementation of chat, messaging, and social features in BimStreaming. The system uses Riverpod for state management, WebSocket for real-time communication, and follows a clean architecture pattern.

## Architecture Overview

### Layer Structure

```
┌─────────────────────────────────────────────────────┐
│                   UI/Screens Layer                   │
│  (friends_screen.dart, dm_screen.dart, etc.)        │
└─────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────┐
│            Riverpod Providers & Controllers           │
│        (data_providers.dart, realtime_controller)    │
└─────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────┐
│              API Client & WebSocket                   │
│      (api_client.dart, WebSocket stream)             │
└─────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────┐
│                 Backend Server (Go)                  │
│         HTTP/WebSocket Endpoints                     │
└─────────────────────────────────────────────────────┘
```

## Core Components

### 1. Data Models (`lib/app/state/data_providers.dart`)

#### Friend
Represents a friend or user in the system:
- `id` - Unique user identifier
- `name` - User's display name
- `avatar` - Avatar URL/image
- `isOnline` - Current online status
- `lastSeen` - When user was last online

#### DMMessage
Represents a direct message:
- `id` - Message identifier
- `conversationId` - Which conversation this belongs to
- `senderId` - Who sent the message
- `senderName` - Display name of sender
- `body` - Message text content
- `sentAt` - Timestamp
- `editedAt` - When edited (if applicable)
- `reactions` - Emoji reactions with counts
- `readBy` - Set of user IDs who read this
- `replyTo` - Reference to another message (for replies)
- `attachments` - List of attachment URLs

#### DMConversation
Represents a DM conversation thread:
- `userId` - The other participant
- `userName` - Their display name
- `avatar` - Their avatar
- `lastMessage` - Preview of last message
- `lastMessageTime` - When it was sent
- `unreadCount` - Unread messages
- `isTyping` - If they're currently typing

#### Community
Represents a community/group:
- `id` - Community identifier
- `name` - Community name
- `description` - About this community
- `icon` - Emoji or icon representing community
- `memberCount` - Total members
- `isMember` - If current user is a member

#### AppNotification
Represents an in-app notification:
- `id` - Notification ID
- `title` - Short title
- `message` - Detailed message
- `type` - Type (friend_request, message, mention, etc.)
- `createdAt` - When created
- `read` - Has user seen it
- `actionUrl` - Where to navigate when tapped

#### RemoteSession
Represents a remote support session:
- `id` - Session ID
- `deviceId` - Device being controlled
- `partnerName` - Name of remote party
- `sessionCode` - Join code
- `startedAt` - When session started
- `status` - active/ended
- `duration` - Total duration if ended

### 2. State Controllers

#### FriendsController
Manages friend list, requests, and blocking:

```dart
// Load all friends, pending requests, and blocked users
Future<void> loadFriends()

// Send friend request to a user
Future<void> sendFriendRequest(String userId)

// Accept pending request
Future<void> acceptFriendRequest(String userId)

// Decline pending request
Future<void> declineFriendRequest(String userId)

// Remove a friend
Future<void> removeFriend(String userId)

// Block a user
Future<void> blockUser(String userId)

// Update friend's online status (called by WebSocket)
void updateFriendOnlineStatus(String userId, bool isOnline)
```

#### MessagesController
Manages DM conversations and messages:

```dart
// Load all conversations
Future<void> loadConversations()

// Load messages for specific user
Future<void> loadMessages(String userId)

// Send a message
Future<void> sendMessage(String userId, String body)

// Edit a message
Future<void> editMessage(String userId, String messageId, String body)

// Delete a message
Future<void> deleteMessage(String userId, String messageId)

// Update typing indicator
void setTypingStatus(String userId, bool isTyping)

// Add message received via WebSocket
void addMessage(String userId, DMMessage message)
```

#### CommunitiesController
Manages communities:

```dart
// Load all communities
Future<void> loadCommunities()

// Join a community
Future<void> joinCommunity(String communityId)

// Leave a community
Future<void> leaveCommunity(String communityId)
```

#### NotificationsController
Manages notifications:

```dart
// Load all notifications
Future<void> loadNotifications()

// Mark notification as read
Future<void> markAsRead(String notificationId)

// Add notification (called by WebSocket)
void addNotification(AppNotification notification)
```

#### RemoteSessionsController
Manages remote session history:

```dart
// Load session history and device info
Future<void> loadSessions()
```

### 3. Realtime Controller (`realtime_controller.dart`)

The `RealtimeController` bridges WebSocket events to the data providers:

```dart
// Set up WebSocket event handlers
Future<void> setupWSHandlers()

// Handle individual WebSocket message
void _handleWSMessage(WSMessage message)
```

**WebSocket Event Types:**
- `user:online` - User came online
- `user:offline` - User went offline
- `dm:new` - New direct message received
- `dm:typing` - User started typing
- `dm:typing_stop` - User stopped typing
- `friend:request` - Incoming friend request
- `friend:accepted` - Friend request was accepted
- `remote:invite` - Remote session invite
- `notification:new` - Generic notification
- `community:message` - New community message
- `community:announcement` - Community announcement

### 4. Riverpod Providers

```dart
// API Client for making HTTP requests
final apiClientProvider = Provider<ApiClient>(...)

// Friend list and requests
final friendsControllerProvider = StateNotifierProvider<FriendsController, FriendsState>(...)

// Direct messages
final messagesControllerProvider = StateNotifierProvider<MessagesController, MessagesState>(...)

// Communities
final communitiesControllerProvider = StateNotifierProvider<CommunitiesController, CommunitiesState>(...)

// Notifications
final notificationsControllerProvider = StateNotifierProvider<NotificationsController, NotificationsState>(...)

// Remote sessions
final remoteSessionsControllerProvider = StateNotifierProvider<RemoteSessionsController, RemoteSessionsState>(...)

// WebSocket stream
final wsProvider = StreamProvider.autoDispose<WSMessage>(...)

// Realtime controller
final realtimeControllerProvider = Provider<RealtimeController>(...)
```

## UI Components

### Screen: Friends (`friends_screen.dart`)

**Features:**
- List all friends with online status
- View pending friend requests
- View blocked users
- Send friend request to new users
- Accept/decline requests
- Block/unblock users
- Remove friends

**Widgets:**
- `FriendsScreen` - Main screen with tabs
- `FriendsList` - List of friends
- `FriendRequestsList` - Pending requests
- `BlockedList` - Blocked users

### Screen: Direct Messages (`dm_screen.dart`)

**Features:**
- List all conversations
- Show unread counts
- Display typing indicators
- Send/receive messages
- Message reactions
- Read receipts
- Message editing/deletion

**Widgets:**
- `DMScreen` - Conversation list
- `ConversationsList` - List view
- `DMConversationScreen` - Individual conversation
- `MessageBubble` - Single message display
- `MessageInputField` - Message composer
- `TypingIndicator` - Animated typing indicator

### Screen: Notifications (`notifications_screen.dart`)

**Features:**
- List all notifications
- Mark as read
- Filter by type
- Navigate to related content
- Show unread count badge

**Widgets:**
- `NotificationsScreen` - Main notifications view
- `NotificationsList` - List view
- `NotificationTile` - Single notification
- `NotificationBadge` - Badge for app bar

### Screen: Communities (`communities_screen.dart`)

**Features:**
- Browse available communities
- Join/leave communities
- View community details
- See member count
- View community feed (placeholder)

**Widgets:**
- `CommunitiesScreen` - List of communities
- `CommunitiesList` - Grid/list view
- `CommunityCard` - Community card
- `CommunityDetailScreen` - Detailed view

## Navigation

Routes are defined in `lib/app/router.dart`:

```
/app/friends                    - Friends list
/app/messages                   - Conversations list
/app/messages/:userId           - Specific conversation
/app/communities                - Communities list
/app/communities/:communityId   - Community details
/app/notifications              - Notifications center
```

## API Endpoints Required

The backend (Go server) must implement these endpoints:

### Friends Endpoints
```
GET    /api/v1/friends                          - Get friends, pending, blocked
POST   /api/v1/friends/request/:userId          - Send friend request
POST   /api/v1/friends/request/:userId/accept   - Accept request
POST   /api/v1/friends/request/:userId/decline  - Decline request
DELETE /api/v1/friends/:userId                  - Remove friend
POST   /api/v1/friends/block/:userId            - Block user
```

### Messages Endpoints
```
GET    /api/v1/dm                               - Get conversations
GET    /api/v1/dm/:userId                       - Get messages with user
POST   /api/v1/dm/:userId                       - Send message
PATCH  /api/v1/dm/:userId/message/:messageId    - Edit message
DELETE /api/v1/dm/:userId/message/:messageId    - Delete message
```

### Communities Endpoints
```
GET    /api/v1/communities                      - Get communities
POST   /api/v1/communities/:communityId/join    - Join community
POST   /api/v1/communities/:communityId/leave   - Leave community
```

### Notifications Endpoints
```
GET    /api/v1/notifications                    - Get all notifications
POST   /api/v1/notifications/:notificationId/read - Mark as read
```

### Remote Sessions Endpoints
```
GET    /api/v1/remote/history                   - Get session history
```

### WebSocket Endpoint
```
WS     /api/v1/ws                               - WebSocket connection
```

## Data Flow Example: Receiving a Message

1. **Backend sends WebSocket event:**
   ```json
   {
     "type": "dm:new",
     "data": {
       "id": "msg123",
       "from_user_id": "user456",
       "from_user_name": "John Doe",
       "body": "Hello!",
       "sent_at": "2024-01-15T10:30:00Z"
     }
   }
   ```

2. **RealtimeController receives and processes:**
   ```dart
   case 'dm:new':
     final userId = message.data['from_user_id'] as String?;
     final body = message.data['body'] as String?;
     if (userId != null && body != null) {
       final msg = DMMessage(...);
       ref.read(messagesControllerProvider.notifier).addMessage(userId, msg);
     }
   ```

3. **MessagesController updates state:**
   ```dart
   void addMessage(String userId, DMMessage message) {
     final updated = Map.of(state.messagesByUserId);
     if (updated[userId] == null) updated[userId] = [];
     updated[userId] = [...updated[userId]!, message];
     state = state.copyWith(messagesByUserId: updated);
   }
   ```

4. **UI automatically updates** via Riverpod reactivity

## State Management Pattern

The implementation follows Riverpod's StateNotifier pattern:

```dart
// State is immutable
class MyState {
  const MyState({
    required this.items,
    this.isLoading = false,
    this.error,
  });
  
  final List<Item> items;
  final bool isLoading;
  final String? error;
  
  MyState copyWith({...}) => MyState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    error: error ?? this.error,
  );
}

// Controller manages state transitions
class MyController extends StateNotifier<MyState> {
  MyController(this._api) : super(const MyState(items: []));
  
  Future<void> loadItems() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _api.getItems();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

// Provider exposes controller
final myControllerProvider = StateNotifierProvider<MyController, MyState>((ref) {
  return MyController(ref.watch(apiClientProvider));
});

// Consume in UI
final state = ref.watch(myControllerProvider);
ref.read(myControllerProvider.notifier).loadItems();
```

## WebSocket Setup

The WebSocket is automatically managed:

1. **Connection happens in AppShell.initState():**
   ```dart
   ref.read(realtimeControllerProvider).setupWSHandlers();
   ```

2. **WSProvider maintains connection:**
   ```dart
   final wsProvider = StreamProvider.autoDispose<WSMessage>((ref) {
     final channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8080/api/v1/ws'));
     return channel.stream.map((message) => WSMessage.fromJson(...));
   });
   ```

3. **RealtimeController listens:**
   ```dart
   ref.listen<AsyncValue<WSMessage>>(wsProvider, (previous, next) {
     next.whenData((message) => _handleWSMessage(message));
   });
   ```

## API Client Usage

The `ApiClient` is injected via Riverpod:

```dart
// In controller
final client = ApiClient();

// Make requests
final data = await client.get('/endpoint');
final result = await client.post('/endpoint', body: {'key': 'value'});
await client.patch('/endpoint', body: data);
await client.delete('/endpoint');

// Authentication
client.setAuthToken('your-jwt-token');
```

## Error Handling

Errors are tracked in state and displayed in UI:

```dart
if (state.error != null) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(state.error!)),
  );
}

// Retry logic
ElevatedButton(
  onPressed: () => ref.read(friendsControllerProvider.notifier).loadFriends(),
  child: const Text('Retry'),
)
```

## Future Enhancements

Planned features:
- Message search
- Custom reactions/emojis
- File/media sharing
- Voice messages
- Video calls
- Message pinning
- Community moderation
- User bans/muting
- Scheduled messages
- Message encryption

## Testing

To test the chat features:

1. **Start backend server:**
   ```bash
   cd server
   go run main.go
   ```

2. **Start Flutter app:**
   ```bash
   cd client
   flutter run
   ```

3. **Test flows:**
   - Login with two different users
   - Send friend request
   - Send direct message
   - Join community
   - Check notifications

## Troubleshooting

### WebSocket Connection Failed
- Check backend is running on `localhost:8080`
- Verify WebSocket endpoint is `/api/v1/ws`
- Check browser console for connection errors

### Messages Not Appearing
- Check Riverpod DevTools if available
- Verify API endpoints match backend implementation
- Check network tab for failed requests

### Typing Indicator Not Working
- Ensure `dm:typing` and `dm:typing_stop` events are sent by backend
- Check RealtimeController is properly handling events

### Unread Count Not Updating
- Verify backend sends unread counts in DM responses
- Check `DMConversation.unreadCount` is being updated

## Summary

This architecture provides:
- ✅ Real-time messaging with WebSocket
- ✅ Friend management and requests
- ✅ Community support
- ✅ Notifications system
- ✅ Reactive UI with Riverpod
- ✅ Clean separation of concerns
- ✅ Easy to test and extend

The system is designed to be scalable and maintainable, with clear data flows and proper state management.
