import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../screens/communities_screen.dart';
import '../../screens/dm_screen.dart';
import '../../screens/friends_screen.dart';
import '../../screens/notifications_screen.dart';
import '../layout/app_shell.dart';

final routerProvider = GoRouter(
  initialLocation: '/home',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        // Home/Chat routes
        GoRoute(
          path: '/home',
          name: 'home',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Home'))),
        ),
        // Friends routes
        GoRoute(
          path: '/friends',
          name: 'friends',
          builder: (context, state) => const FriendsScreen(),
        ),
        // Messages routes
        GoRoute(
          path: '/dm',
          name: 'dm',
          builder: (context, state) => const DMScreen(),
        ),
        GoRoute(
          path: '/dm/:userId',
          name: 'dm-conversation',
          builder: (context, state) {
            final userId = state.pathParameters['userId'] ?? '';
            return DMConversationScreen(userId: userId);
          },
        ),
        // Communities routes
        GoRoute(
          path: '/communities',
          name: 'communities',
          builder: (context, state) => const CommunitiesScreen(),
        ),
        GoRoute(
          path: '/communities/:communityId',
          name: 'community-detail',
          builder: (context, state) {
            final communityId = state.pathParameters['communityId'] ?? '';
            return CommunityDetailScreen(communityId: communityId);
          },
        ),
        // Notifications route
        GoRoute(
          path: '/notifications',
          name: 'notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),
      ],
    ),
  ],
);
