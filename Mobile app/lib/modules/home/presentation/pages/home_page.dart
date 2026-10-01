import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:roadguard_ai/core/theme/app_theme.dart';

/// Map, alerts and profile match the supplied traveler design.
/// The router owns selection so deep links and back navigation stay in sync.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.path, required this.child});

  final String path;
  final Widget child;
  static const _paths = [
    HomePaths.explore,
    HomePaths.alerts,
    ProfilePaths.profile,
  ];

  @override
  Widget build(BuildContext context) {
    final index = _paths.contains(path) ? _paths.indexOf(path) : 2;
    return Scaffold(
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: Container(
        height: 69,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE1E8E8))),
        ),
        child: Row(
          children: [
            _BottomNavTab(
              label: 'Explore',
              icon: Icons.explore_outlined,
              activeIcon: Icons.explore,
              isActive: index == 0,
              onTap: () => context.go(HomePaths.explore),
            ),
            _BottomNavTab(
              label: 'Alerts',
              icon: Icons.notifications_outlined,
              activeIcon: Icons.notifications,
              isActive: index == 1,
              onTap: () => context.go(HomePaths.alerts),
            ),
            _BottomNavTab(
              label: 'Profile',
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              isActive: index == 2,
              onTap: () => context.go(ProfilePaths.profile),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavTab extends StatelessWidget {
  const _BottomNavTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  // Material Design icons: outlined normally, filled for the current tab
  // (Material's navigation bar pattern). Real icons, not text characters,
  // so they look the same on every phone.
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    // Tells screen readers this is a tab button and whether it's the current
    // one (the standard NavigationBar did this automatically).
    child: Semantics(
      key: Key('nav-${label.toLowerCase()}'),
      container: true,
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                size: 26,
                color: isActive ? RoadColors.blue : const Color(0xFF657781),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isActive ? RoadColors.blue : const Color(0xFF657781),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
