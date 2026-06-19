import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('product display name', () {
    test('uses GoPic in user-visible platform metadata', () {
      expect(
        File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync(),
        contains('PRODUCT_NAME = GoPic'),
      );
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        allOf(
          contains('<string>GoPic</string>'),
          isNot(contains('Flutter Gopic')),
        ),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:label="GoPic"'),
      );
      expect(
        File('web/manifest.json').readAsStringSync(),
        allOf(contains('"name": "GoPic"'), contains('"short_name": "GoPic"')),
      );
      expect(
        File('web/index.html').readAsStringSync(),
        allOf(contains('content="GoPic"'), contains('<title>GoPic</title>')),
      );
      expect(
        File('linux/runner/my_application.cc').readAsStringSync(),
        contains('"GoPic"'),
      );
      expect(
        File('windows/runner/main.cpp').readAsStringSync(),
        contains('L"GoPic"'),
      );
      expect(
        File('windows/runner/Runner.rc').readAsStringSync(),
        allOf(
          contains('VALUE "FileDescription", "GoPic"'),
          contains('VALUE "ProductName", "GoPic"'),
        ),
      );
    });
  });
}
