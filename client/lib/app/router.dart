import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/auth/forgot_password_screen.dart';
import 'pages/auth/login_screen.dart';
import 'pages/auth/register_wizard_screen.dart';
import 'pages/auth/reset_code_screen.dart';
import 'pages/auth/new_password_screen.dart';
import 'pages/auth/two_factor_screen.dart';
import 'pages/community_settings_screen.dart';
import 'pages/home_screen.dart';
import 'pages/profile_screen.dart';
import 'pages/settings_screen.dart';
import 'state/auth_controller.dart';
import 'widgets/app_shell.dart';
import '../screens/dm_screen.dart';
import '../screens/friends_screen.dart' as new_friends;
import '../screens/notifications_screen.dart' as new_notifications;
import '../screens/communities_screen.dart' as new_communities;

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/auth/login',
    redirect: (context, state) {
      if (auth.isLoading) {
        return null;
      }

      final onAuthRoute = state.matchedLocation.startsWith('/auth');
      final signedIn = auth.isAuthenticated;
      final twoFactorPending = auth.stage == AuthStage.twoFactorRequired;

      if (!signedIn && !twoFactorPending && !onAuthRoute) {
        return '/auth/login';
      }

      if (twoFactorPending && state.matchedLocation != '/auth/2fa') {
        return '/auth/2fa';
      }

      if (signedIn && onAuthRoute) {
        return '/app/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/2fa',
        builder: (context, state) => const TwoFactorScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterWizardScreen(),
      ),
      GoRoute(
        path: '/auth/forgot',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/reset-code',
        builder: (context, state) {
          final email = state.extra as String?;
          if (email == null) {
            return const LoginScreen();
          }
          return ResetCodeScreen(email: email);
        },
      ),
      GoRoute(
        path: '/auth/new-password',
        builder: (context, state) {
          final email = state.extra as String?;
          final code = state.uri.queryParameters['code'] ?? '';
          if (email == null || code.isEmpty) {
            return const LoginScreen();
          }
          return NewPasswordScreen(email: email, code: code);
        },
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(location: state.matchedLocation, child: child);
        },
        routes: [
          GoRoute(
            path: '/app/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/app/profile',
            builder: (context, state) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: ':userId',
                builder: (context, state) =>
                    ProfileScreen(userId: state.pathParameters['userId']),
              ),
            ],
          ),
          GoRoute(
            path: '/app/friends',
            builder: (context, state) => const new_friends.FriendsScreen(),
          ),
          GoRoute(
            path: '/app/messages',
            builder: (context, state) => const DMScreen(),
            routes: [
              GoRoute(
                path: ':userId',
                builder: (context, state) => DMConversationScreen(
                  userId: state.pathParameters['userId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/app/communities',
            builder: (context, state) =>
                const new_communities.CommunitiesScreen(),
            routes: [
              GoRoute(
                path: ':communityId',
                builder: (context, state) =>
                    new_communities.CommunityDetailScreen(
                      communityId: state.pathParameters['communityId'] ?? '',
                    ),
              ),
            ],
          ),
          GoRoute(
            path: '/app/communities/settings',
            builder: (context, state) => const CommunitySettingsScreen(),
          ),
          GoRoute(
            path: '/app/notifications',
            builder: (context, state) =>
                const new_notifications.NotificationsScreen(),
          ),
          GoRoute(
            path: '/app/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
