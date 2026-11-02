import 'dart:async';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/auth_session.dart';
import 'features/auth/session_status_page.dart';

class SmartNutritionApp extends StatefulWidget {
  const SmartNutritionApp({this.session, super.key});
  final AuthSession? session;

  @override
  State<SmartNutritionApp> createState() => _SmartNutritionAppState();
}

class _SmartNutritionAppState extends State<SmartNutritionApp>
    with WidgetsBindingObserver {
  late final _session = widget.session ?? AuthSession();
  bool _hasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_session.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _session.checkExpiry();
      unawaited(_session.refreshUser());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthSessionScope(
      session: _session,
      child: ListenableBuilder(
        listenable: _session,
        builder: (context, child) {
          final authenticated = _session.isAuthenticated;
          if (authenticated) _hasAuthenticated = true;
          return MaterialApp(
            // Changing authentication discards the entire old Navigator, including
            // anonymous nested routes and protected screens kept offstage.
            key: ValueKey(authenticated),
            title: 'Smart Nutrition',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            builder: (context, child) => _session.isBlocking
                ? SessionStatusPage(session: _session)
                : child!,
            onGenerateRoute: AuthGate.route,
            // Resolve startup/deep links through the same public route allowlist.
            onGenerateInitialRoutes: (name) =>
                authenticated || _hasAuthenticated || _session.hasEndedSession
                ? [AuthGate.route(const RouteSettings(name: '/'))]
                : [
                    // Public entry pages must have a safe login route to return to.
                    if (const [
                      '/register',
                      '/email-verification',
                      '/forgot-password',
                    ].contains(name))
                      AuthGate.route(const RouteSettings(name: '/')),
                    AuthGate.route(RouteSettings(name: name)),
                  ],
          );
        },
      ),
    );
  }
}
