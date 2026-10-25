import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: SafeArea(bottom: false, child: shell),
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) {
        HapticFeedback.selectionClick();
        shell.goBranch(i, initialLocation: i == shell.currentIndex);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.wb_twilight_rounded), label: 'Today'),
        NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'Progress'),
        NavigationDestination(icon: Icon(Icons.forum_rounded), label: 'Coach'),
        NavigationDestination(icon: Icon(Icons.auto_stories_rounded), label: 'Library'),
        NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
      ],
    ),
  );
}
