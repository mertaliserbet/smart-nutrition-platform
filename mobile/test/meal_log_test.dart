import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/nutrition/manual_meal_log_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_page.dart';

void main() {
  testWidgets('nutrition opens the form and back preserves its selected tab', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartNutritionApp());
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Beslenme'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Öğün listesi henüz kullanıma açık değil.'),
      findsOneWidget,
    );
    expect(find.text('Henüz öğün yok'), findsNothing);

    await tapVisible(tester, find.text('Öğün ekle'));
    expect(find.byType(ManualMealLogPage), findsOneWidget);
    await tester.enterText(mealField('Yemek adı'), 'Sentetik öğün');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NutritionPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tapVisible(tester, find.text('Öğün ekle'));
    expect(
      tester.widget<TextFormField>(mealField('Yemek adı')).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard shortcut opens the same form without changing demo data',
    (tester) async {
      await tester.pumpWidget(const SmartNutritionApp());
      await tapVisible(tester, find.text('Öğün ekle'));
      expect(find.byType(ManualMealLogPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.text('1680'), findsOneWidget);
      expect(find.text('1250 mL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'starts empty with explicit preview and unknown nutrition values',
    (tester) async {
      await pumpMealForm(tester);
      expect(find.text('Önizleme · Kayıt oluşturulmaz'), findsOneWidget);
      expect(find.text('Kalori ve makro bilgisi yok'), findsOneWidget);
      expect(find.text('Cihazınızın yerel saati'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(mealField('Yemek adı')).controller!.text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(mealField('Miktar (gram)'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .every((chip) => !chip.selected),
        isTrue,
      );
      expect(find.textContaining('kcal'), findsNothing);
      expect(find.text('Kaydet'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Yemek adını girin.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'validates missing meal type and whitespace name without requiring grams',
    (tester) async {
      await pumpMealForm(tester);
      await tester.enterText(mealField('Yemek adı'), '   ');
      await tapVisible(tester, find.text('Bilgileri kontrol et'));
      expect(find.text('Bir öğün türü seçin.'), findsOneWidget);
      expect(find.text('Yemek adını girin.'), findsOneWidget);
      expect(find.textContaining('Sıfırdan büyük'), findsNothing);
      expect(find.byKey(const ValueKey('mealLogUnavailable')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'meal selection remains exclusive across all four canonical choices',
    (tester) async {
      await pumpMealForm(tester);
      for (final label in ['Kahvaltı', 'Öğle', 'Akşam', 'Ara öğün']) {
        await tapVisible(tester, find.widgetWithText(ChoiceChip, label));
        final selected = tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((chip) => chip.selected);
        expect(selected, hasLength(1));
        expect((selected.single.label as Text).data, label);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rejects invalid quantities and accepts decimal comma, point and unknown grams',
    (tester) async {
      await pumpMealForm(tester);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Öğle'));
      await tester.enterText(mealField('Yemek adı'), 'Sentetik yemek');

      for (final quantity in [
        '0',
        '-1',
        'abc',
        'NaN',
        'Infinity',
        '1e3',
        '12,3,4',
      ]) {
        await enterQuantity(tester, quantity);
        await tapVisible(tester, find.text('Bilgileri kontrol et'));
        expect(find.textContaining('Sıfırdan büyük'), findsOneWidget);
        expect(find.byKey(const ValueKey('mealLogUnavailable')), findsNothing);
      }
      for (final quantity in ['', '125,5', '125.5']) {
        await enterQuantity(tester, quantity);
        await tapVisible(tester, find.text('Bilgileri kontrol et'));
        expect(find.textContaining('Sıfırdan büyük'), findsNothing);
        expect(
          find.byKey(const ValueKey('mealLogUnavailable')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(mealField('Miktar (gram)'))
              .controller!
              .text,
          quantity,
        );
      }
      expect(find.byType(ManualMealLogPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.textContaining('başarıyla'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'feedback clears when details change and no success or record is generated',
    (tester) async {
      await pumpMealForm(tester);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Kahvaltı'));
      await tester.enterText(mealField('Yemek adı'), 'Sentetik öğün');
      await tapVisible(tester, find.text('Bilgileri kontrol et'));
      expect(
        find.text(
          'Kayıt özelliği henüz kullanıma açık değil. Öğün kaydedilmedi.',
        ),
        findsOneWidget,
      );
      await enterQuantity(tester, '80');
      expect(find.byKey(const ValueKey('mealLogUnavailable')), findsNothing);
      expect(
        tester.widget<TextFormField>(mealField('Yemek adı')).controller!.text,
        'Sentetik öğün',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date and time pickers update consumption time and cancellation keeps it',
    (tester) async {
      await pumpMealForm(tester);
      // Labels are read from rendered buttons, not serialized as API payloads.
      final initialDate = tester
          .widget<Text>(find.textContaining('Tarih: '))
          .data!;
      await tapVisible(tester, find.textContaining('Tarih: '));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(find.text(initialDate), findsOneWidget);

      await tapVisible(tester, find.textContaining('Tarih: '));
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      final calendarDate = calendar.initialDate!;
      final pickedDate = DateTime(
        calendarDate.year,
        calendarDate.month,
        calendarDate.day == 1 ? 2 : 1,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('${pickedDate.day}'),
        ),
      );
      await tester.tap(find.text('Seç'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Tarih: ${pickedDate.day.toString().padLeft(2, '0')}.${pickedDate.month.toString().padLeft(2, '0')}.${pickedDate.year}',
        ),
        findsOneWidget,
      );

      final initialTime = tester
          .widget<Text>(find.textContaining('Saat: '))
          .data!;
      await tapVisible(tester, find.textContaining('Saat: '));
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(find.text(initialTime), findsOneWidget);
      await tapVisible(tester, find.textContaining('Saat: '));
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final timeInputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(timeInputs.at(0), '09');
      await tester.enterText(timeInputs.at(1), '35');
      await tester.tap(find.text('Seç'));
      await tester.pumpAndSettle();
      expect(find.text('Saat: 09:35'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    for (final viewport in [
      (size: const Size(320, 640), scale: 2.0, keyboard: 220.0),
      (size: const Size(568, 320), scale: 1.5, keyboard: 120.0),
      (size: const Size(900, 1000), scale: 1.0, keyboard: 0.0),
    ]) {
      testWidgets(
        'meal form supports ${viewport.size}, ${viewport.scale}x and keyboard in ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.size;
          tester.view.viewInsets = FakeViewPadding(bottom: viewport.keyboard);
          tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await pumpMealForm(tester);
          expect(
            Theme.of(tester.element(find.byType(ManualMealLogPage))).brightness,
            brightness,
          );
          for (final label in [
            'Yemek adı',
            'Miktar (gram)',
            'Bilgileri kontrol et',
          ]) {
            final target = label == 'Bilgileri kontrol et'
                ? find.text(label)
                : mealField(label);
            await Scrollable.ensureVisible(
              tester.element(target),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            expect(target.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tapVisible(tester, find.text('Bilgileri kontrol et'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Finder mealField(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

Future<void> pumpMealForm(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: const ManualMealLogPage(),
  ),
);

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> enterQuantity(WidgetTester tester, String quantity) async {
  final field = mealField('Miktar (gram)');
  await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.enterText(field, quantity);
  await tester.pump();
}
