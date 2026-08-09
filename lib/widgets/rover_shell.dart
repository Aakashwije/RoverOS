import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

/// Shell around the tabbed portrait screens.
///
/// DRIVE sits in the tab bar because it is the app's headline action, but it is
/// not a branch: it pushes a full-screen landscape route over the shell, then
/// returns the user to whichever tab they came from.
class RoverShell extends StatelessWidget {
  const RoverShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: shell,
      bottomNavigationBar: RoverNavBar(
        currentBranch: shell.currentIndex,
        onSelectBranch: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        onDrive: () => context.push(AppRoute.drive),
      ),
    );
  }
}

class _NavDestination {
  const _NavDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.branchIndex,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// `null` for DRIVE, which pushes a route instead of switching branches.
  final int? branchIndex;

  bool get isBranch => branchIndex != null;
}

/// Custom bottom navigation.
///
/// Built by hand rather than with [NavigationBar] so the DRIVE action can carry
/// its own accent treatment and so the active indicator matches the dashboard's
/// instrument styling.
class RoverNavBar extends StatelessWidget {
  const RoverNavBar({
    super.key,
    required this.currentBranch,
    required this.onSelectBranch,
    required this.onDrive,
  });

  final int currentBranch;
  final ValueChanged<int> onSelectBranch;
  final VoidCallback onDrive;

  static const List<_NavDestination> _destinations = [
    _NavDestination(
      label: 'HOME',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
      branchIndex: 0,
    ),
    _NavDestination(
      label: 'DRIVE',
      icon: Icons.sports_esports_outlined,
      activeIcon: Icons.sports_esports_rounded,
    ),
    _NavDestination(
      label: 'AUTO',
      icon: Icons.auto_mode_outlined,
      activeIcon: Icons.auto_mode_rounded,
      branchIndex: 1,
    ),
    _NavDestination(
      label: 'SETTINGS',
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune_rounded,
      branchIndex: 2,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.raised,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final destination in _destinations)
                Expanded(
                  child: _NavItem(
                    destination: destination,
                    isActive: destination.branchIndex == currentBranch,
                    onTap: () => destination.isBranch
                        ? onSelectBranch(destination.branchIndex!)
                        : onDrive(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.isActive,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDriveAction = !destination.isBranch;
    final color = isActive
        ? AppColors.accent
        : isDriveAction
        ? AppColors.textPrimary
        : AppColors.textTertiary;

    return Semantics(
      button: true,
      selected: isActive,
      label: isDriveAction
          ? 'Drive. Opens the landscape driving controls'
          : destination.label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.accentGlow,
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Active tab marker, so selection is not carried by colour alone.
              AnimatedContainer(
                duration: AppDurations.normal,
                curve: AppDurations.standard,
                height: 3,
                width: isActive ? 26 : 0,
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: AppRadii.pillRadius,
                ),
              ),
              Icon(
                isActive ? destination.activeIcon : destination.icon,
                size: 22,
                color: color,
              ),
              const SizedBox(height: 4),
              Text(
                destination.label,
                style: AppTypography.label.copyWith(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
