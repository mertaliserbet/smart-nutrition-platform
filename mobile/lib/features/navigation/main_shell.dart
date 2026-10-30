import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../home/home_page.dart';
import '../nutrition/nutrition_page.dart';
import '../profile/profile_page.dart';
import '../progress/progress_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Ana Sayfa',
    ),
    NavigationDestination(
      icon: Icon(Icons.restaurant_outlined),
      selectedIcon: Icon(Icons.restaurant_rounded),
      label: 'Beslenme',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights_rounded),
      label: 'İlerleme',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Profil',
    ),
  ];

  int _selectedIndex = 0;

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _selectTab(0);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: false,
          titleSpacing: AppTokens.spacingLarge,
          title: Text(
            _selectedIndex == 0
                ? 'Smart Nutrition'
                : _destinations[_selectedIndex].label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              HomePage(onViewNutrition: () => _selectTab(1)),
              const NutritionPage(),
              const ProgressPage(),
              const ProfilePage(),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spacingMedium,
              AppTokens.spacingSmall,
              AppTokens.spacingMedium,
              AppTokens.spacingMedium,
            ),
            child: Material(
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
                side: BorderSide(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectTab,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                backgroundColor: Colors.transparent,
                indicatorColor: colors.primaryContainer,
                elevation: 0,
                destinations: _destinations,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
