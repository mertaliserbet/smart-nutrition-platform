import 'package:flutter/material.dart';

import '../home/home_page.dart';
import '../nutrition/nutrition_page.dart';
import '../profile/profile_page.dart';
import '../progress/progress_page.dart';
import '../chat/chat_page.dart';
import '../onboarding/onboarding_theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({this.initialIndex = 0, this.onLogout, super.key});
  final int initialIndex;
  final Future<void> Function()? onLogout;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _destinations = [
    NavigationDestination(
      icon: OnboardingIcon('house', size: 25),
      label: 'Günüm',
    ),
    NavigationDestination(
      icon: OnboardingIcon('chart-no-axes-column', size: 25),
      label: 'Ölçüm',
    ),
    NavigationDestination(
      icon: OnboardingIcon('calendar', size: 25),
      label: 'Planım',
    ),
    NavigationDestination(
      icon: OnboardingIcon('message-circle', size: 25),
      label: 'Sohbet',
    ),
    NavigationDestination(
      icon: OnboardingIcon('user-round', size: 25),
      label: 'Hesabım',
    ),
  ];

  late int _selectedIndex = widget.initialIndex;
  int _nutritionRevision = 0;
  int _measurementRevision = 0;
  int _chatRevision = 0;
  int _profileRevision = 0;

  void _selectTab(int index) {
    if (index == _selectedIndex) {
      if (index == 0 || index == 2) setState(() => ++_nutritionRevision);
      if (index == 1) setState(() => ++_measurementRevision);
      if (index == 3) setState(() => ++_chatRevision);
      if (index == 4) setState(() => ++_profileRevision);
      return;
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _selectTab(0);
      },
      child: Scaffold(
        backgroundColor: OnboardingTheme.background,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              HomePage(
                active: _selectedIndex == 0,
                refreshRevision: _nutritionRevision,
                onViewNutrition: () => _selectTab(2),
                onViewProfile: () => _selectTab(4),
              ),
              ProgressPage(
                active: _selectedIndex == 1,
                refreshRevision: _measurementRevision,
                onViewProfile: () => _selectTab(4),
              ),
              NutritionPage(
                active: _selectedIndex == 2,
                refreshRevision: _nutritionRevision,
                onViewProfile: () => _selectTab(4),
              ),
              ChatPage(
                active: _selectedIndex == 3,
                refreshRevision: _chatRevision,
                onViewProfile: () => _selectTab(4),
              ),
              ProfilePage(
                active: _selectedIndex == 4,
                refreshRevision: _profileRevision,
                onLogout: widget.onLogout,
              ),
            ],
          ),
        ),
        bottomNavigationBar: Theme(
          data: OnboardingTheme.data.copyWith(
            navigationBarTheme: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13,
                  color: OnboardingTheme.ink,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
          child: ColoredBox(
            color: OnboardingTheme.background,
            child: SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFD7E1D0))),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      NavigationBar(
                        height: 82,
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _selectTab,
                        labelBehavior:
                            NavigationDestinationLabelBehavior.alwaysShow,
                        backgroundColor: OnboardingTheme.background,
                        surfaceTintColor: Colors.transparent,
                        indicatorColor: Colors.transparent,
                        elevation: 0,
                        destinations: _destinations,
                      ),
                      Positioned(
                        left:
                            constraints.maxWidth / 5 * (_selectedIndex + .5) -
                            15.5,
                        bottom: 5,
                        child: IgnorePointer(
                          child: Container(
                            width: 31,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3D7756),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
