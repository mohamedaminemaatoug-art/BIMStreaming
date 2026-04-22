# Chat & Social Features - Quick Reference Guide

## File Structure

```
client/lib/
├── app/
│   ├── state/
│   │   ├── data_providers.dart           ← All data models & controllers
│   │   ├── realtime_controller.dart      ← WebSocket event handling
│   │   └── auth_controller.dart          ← (existing)
│   ├── layout/
│   │   └── app_shell.dart                ← Navigation shell (UPDATED)
│   ├── widgets/
│   │   └── app_shell.dart                ← (existing, navigation)
│   └── router.dart                       ← (UPDATED with new routes)
├── screens/
│   ├── friends_screen.dart               ← Friends list, requests, blocked
│   ├── dm_screen.dart                    ← Messages & conversations
│   ├── notifications_screen.dart         ← Notifications center
│   └── communities_screen.dart           ← Communities browser
├── services/
│   └── api_client.dart                   ← (existing, HTTP client)
├── models/
│   └── user_model.dart                   ← (existing)
└── main.dart                             ← (existing entry point)
```

## Key Providers (One-liner reference)

```dart
// API
final apiClientProvider = Provider<ApiClient>

// Friends
final friendsControllerProvider = StateNotifierProvider<FriendsController, FriendsState>

// Messages
final messagesControllerProvider = StateNotifierProvider<MessagesController, MessagesState>

// Communities
final communitiesControllerProvider = StateNotifierProvider<CommunitiesController, CommunitiesState>

// Notifications
final notificationsControllerProvider = StateNotifierProvider<NotificationsController, NotificationsState>

// Remote Sessions
final remoteSessionsControllerProvider = StateNotifierProvider<RemoteSessionsController, RemoteSessionsState>

// WebSocket
final wsProvider = StreamProvider.autoDispose<WSMessage>

// Realtime
final realtimeControllerProvider = Provider<RealtimeController>
```

## Common Usage Patterns

### Load Friends
```dart
ref.read(friendsControllerProvider.notifier).loadFriends();
```

### Watch Friends State
```dart
final state = ref.watch(friendsControllerProvider);
print(state.friends);        // List<Friend>
print(state.pending);        // List<Friend>
print(state.blocked);        // List<Friend>
print(state.isLoading);      // bool
print(state.error);          // String?
```

### Send Friend Request
```dart
await ref.read(friendsControllerProvider.notifier)
    .sendFriendRequest('userId');
```

### Load Messages
```dart
ref.read(messagesControllerProvider.notifier).loadMessages('userId');
```

### Send Message
```dart
await ref.read(messagesControllerProvider.notifier)
    .sendMessage('userId', 'Hello!');
```

### Update Typing Status
```dart
ref.read(messagesControllerProvider.notifier)
    .setTypingStatus('userId', true);
```

### Get Notifications
```dart
final state = ref.watch(notificationsControllerProvider);
print(state.notifications);  // List<AppNotification>
print(state.unreadCount);    // int
```

### Join Community
```dart
await ref.read(communitiesControllerProvider.notifier)
    .joinCommunity('communityId');
```

## Routes

```
/app/profile                 → User profile
/app/friends                 → Friends list
/app/messages                → Conversations
/app/messages/:userId        → Chat with user
/app/communities             → Community list
/app/communities/:id         → Community details
/app/notifications           → Notifications
/app/settings                → Settings
```

## Navigation Examples

```dart
// Go to a screen
context.go('/app/friends');

// Go to DM with specific user
context.go('/app/messages/user123');

// Go to community
context.go('/app/communities/community456');

// Push new route (keeps back button)
context.push('/app/messages/user123');
```

## WebSocket Events (Backend → Frontend)

```json
// User came online
{"type": "user:online", "data": {"user_id": "123"}}

// User went offline
{"type": "user:offline", "data": {"user_id": "123"}}

// New message received
{"type": "dm:new", "data": {"from_user_id": "123", "body": "Hello", ...}}

// User typing
{"type": "dm:typing", "data": {"from_user_id": "123"}}

// User stopped typing
{"type": "dm:typing_stop", "data": {"from_user_id": "123"}}

// Friend request received
{"type": "friend:request", "data": {"from_user_id": "123", ...}}

// Friend request accepted
{"type": "friend:accepted", "data": {"user_id": "123", ...}}

// Remote session invite
{"type": "remote:invite", "data": {"from_user_id": "123", ...}}

// Notification
{"type": "notification:new", "data": {"title": "...", "message": "...", ...}}

// Community message
{"type": "community:message", "data": {"community_id": "...", ...}}

// Community announcement
{"type": "community:announcement", "data": {"community_id": "...", ...}}
```

## HTTP Endpoints Required

### Friends
```
GET    /api/v1/friends
POST   /api/v1/friends/request/:userId
POST   /api/v1/friends/request/:userId/accept
POST   /api/v1/friends/request/:userId/decline
DELETE /api/v1/friends/:userId
POST   /api/v1/friends/block/:userId
```

### Messages
```
GET    /api/v1/dm
GET    /api/v1/dm/:userId
POST   /api/v1/dm/:userId
PATCH  /api/v1/dm/:userId/message/:messageId
DELETE /api/v1/dm/:userId/message/:messageId
```

### Communities
```
GET    /api/v1/communities
POST   /api/v1/communities/:communityId/join
POST   /api/v1/communities/:communityId/leave
```

### Notifications
```
GET    /api/v1/notifications
POST   /api/v1/notifications/:notificationId/read
```

### Remote Sessions
```
GET    /api/v1/remote/history
```

### WebSocket
```
WS     /api/v1/ws
```

## Expected API Response Formats

### GET /api/v1/friends
```json
{
  "friends": [
    {
      "id": "user1",
      "name": "John",
      "avatar": "https://...",
      "is_online": true,
      "last_seen": "2024-01-15T10:30:00Z"
    }
  ],
  "pending": [...],
  "blocked": [...]
}
```

### GET /api/v1/dm
```json
{
  "conversations": [
    {
      "user_id": "user1",
      "user_name": "John",
      "avatar": "https://...",
      "last_message": "Hey there!",
      "last_message_time": "2024-01-15T10:30:00Z",
      "unread_count": 2,
      "is_typing": false
    }
  ]
}
```

### GET /api/v1/dm/:userId
```json
{
  "messages": [
    {
      "id": "msg1",
      "sender_id": "user1",
      "sender_name": "John",
      "body": "Hello!",
      "sent_at": "2024-01-15T10:30:00Z",
      "edited_at": null,
      "reactions": {"👍": 1},
      "read_by": ["me", "user1"],
      "reply_to": null,
      "attachments": []
    }
  ]
}
```

### GET /api/v1/communities
```json
{
  "communities": [
    {
      "id": "comm1",
      "name": "Flutter Devs",
      "description": "...",
      "icon": "🚀",
      "member_count": 234,
      "is_member": true
    }
  ]
}
```

### GET /api/v1/notifications
```json
{
  "notifications": [
    {
      "id": "notif1",
      "title": "Friend Request",
      "message": "John sent you a friend request",
      "type": "friend_request",
      "created_at": "2024-01-15T10:30:00Z",
      "read": false,
      "action_url": "/app/friends"
    }
  ]
}
```

## Debugging Tips

### Check Riverpod State
```dart
// In Flutter DevTools, look for Provider states
// Or add logging:
final state = ref.watch(friendsControllerProvider);
print('Friends: ${state.friends.length}');
print('Pending: ${state.pending.length}');
print('Error: ${state.error}');
```

### Watch WebSocket Events
```dart
// In terminal where Flutter app runs, check for:
// - Connection messages
// - Message arrival logs
// - Error logs
```

### Test API Endpoints
```bash
# Friends
curl http://localhost:8080/api/v1/friends \
  -H "Authorization: Bearer TOKEN"

# Send message
curl -X POST http://localhost:8080/api/v1/dm/user123 \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"body": "Hello"}'
```

## Performance Considerations

- **Pagination**: Implement for large message/friend lists
- **Image Caching**: Cache avatars locally
- **Message Pagination**: Load messages in chunks
- **Debouncing**: Typing indicator updates (don't send every keystroke)
- **Lazy Loading**: Load messages on scroll up
- **Unread Badges**: Update efficiently using Riverpod selectors

## Security Considerations

- ✅ Auth token stored securely (check with auth_service)
- ✅ WebSocket connection over WSS (in production)
- ✅ API endpoints require Authorization header
- ✅ Input validation on client side
- ⚠️ Server-side validation required
- ⚠️ Rate limiting for API endpoints
- ⚠️ CORS handling for API

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| WebSocket won't connect | Check backend is running on :8080, endpoint is /api/v1/ws |
| Messages not appearing | Verify `dm:new` event is emitted by backend |
| Typing indicator stuck | Ensure `dm:typing_stop` is sent when user stops typing |
| Unread count not updating | Check API response includes `unread_count` |
| Friends list empty | Call `loadFriends()` after auth |
| Notifications duplicate | Check backend doesn't emit same event twice |

## Example: Complete Message Flow

```dart
// 1. User types in input field
messageController.text = "Hello!";

// 2. User taps send button
onPressed: () {
  ref.read(messagesControllerProvider.notifier)
      .sendMessage(userId, "Hello!");
  messageController.clear();
}

// 3. Controller makes HTTP request to POST /api/v1/dm/:userId
// 4. Backend stores message and broadcasts via WebSocket
// 5. RealtimeController receives event: {"type": "dm:new", ...}
// 6. MessagesController adds message to state via addMessage()
// 7. UI rebuilds and shows new message
// 8. MessageBubble widget displays message with animations
```

## Version Info

- Flutter: 3.x+
- Dart: 3.x+
- Riverpod: ^2.x
- go_router: ^16.x
- http: ^1.x
- web_socket_channel: ^3.x

## Next Steps

1. Implement backend endpoints in Go server
2. Test with two concurrent clients
3. Add message search feature
4. Implement file/media sharing
5. Add voice/video call support
6. Implement message encryption
