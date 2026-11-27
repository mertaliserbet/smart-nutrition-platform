// Opt-in renderer check: flutter run -d <emulator> -t test/day_device_probe.dart --no-pub
// Uses synthetic in-memory responses only; no login, HTTP or account writes.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/home/home_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'day_test_support.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LiveWidgetController(binding);
  final boundary = GlobalKey();
  final session = DayTestSession();
  final errors = <String>[];
  final images = <String, String>{};
  double? navigationBottom;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    debugPrintSynchronously('DAY_RENDER_ERROR ${details.exceptionAsString()}');
  };
  try {
    runApp(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: RepaintBoundary(key: boundary, child: const MainShell()),
        ),
      ),
    );
    await controller.pump(const Duration(milliseconds: 300));
    await controller.pumpAndSettle();
    Future<void> capture(String name) async {
      final bottom = controller.getBottomRight(find.byType(NavigationBar)).dy;
      if (navigationBottom != null && (navigationBottom! - bottom).abs() > 1) {
        throw StateError('Navigation moved while scrolling.');
      }
      navigationBottom = bottom;
      (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .markNeedsPaint();
      await controller.pump(const Duration(milliseconds: 150));
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${Directory.systemTemp.path}/limely-day-$name.png');
      await file.writeAsBytes(data!.buffer.asUint8List());
      images[name] = file.path;
    }

    await capture('01-gunum');
    final scroll = find
        .descendant(
          of: find.byType(HomePage),
          matching: find.byType(Scrollable),
        )
        .first;
    await controller.drag(scroll, const Offset(0, -540));
    await controller.pumpAndSettle();
    await capture('02-ogun');
    await controller.ensureVisible(find.text('Bugünkü planım'));
    await controller.pumpAndSettle();
    await capture('03-plan');
    await controller.ensureVisible(find.byKey(const ValueKey('day-water-add')));
    await controller.pumpAndSettle();
    await controller.tap(find.byKey(const ValueKey('day-water-add')));
    await controller.pumpAndSettle();
    if (session.waterCreates != 1 || session.water != 1000) {
      throw StateError('Water action failed.');
    }
    session.hasPlan = false;
    session.hasMeals = false;
    session.hasTargets = false;
    session.water = 0;
    await controller.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Günüm'),
      ),
    );
    await controller.pumpAndSettle();
    await controller.drag(scroll, const Offset(0, 3000));
    await controller.pumpAndSettle();
    await capture('04-bos-gunum');
    if (errors.isNotEmpty) throw StateError('Renderer reported errors.');
    debugPrintSynchronously(
      'LIMELY_DAY_QA_RESULT ${jsonEncode({'passed': true, 'waterCreateCount': session.waterCreates, 'navigationStayedFixed': true, 'screenshots': images})}',
    );
  } catch (error) {
    debugPrintSynchronously(
      'LIMELY_DAY_QA_RESULT ${jsonEncode({'passed': false, 'error': error.runtimeType.toString(), 'rendererErrors': errors})}',
    );
  }
}
