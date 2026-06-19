import 'package:flutter/material.dart';
import 'package:flutter_gopic/app/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme input hints', () {
    test('uses explicit muted hint colors in light and dark themes', () {
      expect(AppTheme.light.inputDecorationTheme.hintStyle?.color, isNotNull);
      expect(AppTheme.dark.inputDecorationTheme.hintStyle?.color, isNotNull);

      final lightHint = AppTheme.light.inputDecorationTheme.hintStyle!.color!;
      final darkHint = AppTheme.dark.inputDecorationTheme.hintStyle!.color!;

      expect(lightHint, isNot(Colors.black));
      expect(darkHint, isNot(Colors.white));
      expect(lightHint.a, lessThan(1));
      expect(darkHint.a, lessThan(1));
    });
  });
}
