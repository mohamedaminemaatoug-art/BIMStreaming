import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/data_providers.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({Key? key, required this.child}) : super(key: key);

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final messagesState = ref.watch(messagesControllerProvider);
    final notificationsState = ref.watch(notificationsControllerProvider);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          _navigateToIndex(index, context);
        },
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.mail),
                if (messagesState.conversations.any((c) => c.unreadCount > 0))
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.people),
            label: 'Friends',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.groups),
            label: 'Communities',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.notifications),
                if (notificationsState.unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Notifications',
          ),
        ],
      ),
    );
  }

  void _navigateToIndex(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/dm');
        break;
      case 2:
        context.go('/friends');
        break;
      case 3:
        context.go('/communities');
        break;
      case 4:
        context.go('/notifications');
        break;
    }
  }
}
