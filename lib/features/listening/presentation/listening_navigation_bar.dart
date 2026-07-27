import 'package:flutter/material.dart';

import '../../../l10n/display_language.dart';

class ListeningNavigationBar extends StatelessWidget {
  const ListeningNavigationBar({
    required this.onCommunication,
    required this.onHistory,
    super.key,
  });

  final VoidCallback onCommunication;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      key: const Key('listening-bottom-navigation'),
      selectedIndex: 1,
      height: 70,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFF2F1FF),
      onDestinationSelected: (index) {
        if (index == 0) {
          onCommunication();
        } else if (index == 2) {
          onHistory?.call();
        }
      },
      destinations: <NavigationDestination>[
        NavigationDestination(
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: const Icon(Icons.chat_bubble_rounded),
          label: context.tr('Giao tiếp', '交流'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.headphones_outlined),
          selectedIcon: const Icon(Icons.headphones_rounded),
          label: context.tr('Luyện nghe', '听力'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.history_rounded),
          label: context.tr('Lịch sử', '历史'),
          enabled: onHistory != null,
        ),
      ],
    );
  }
}
