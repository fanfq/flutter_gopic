import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gopic/models/cloud_model.dart';
import 'package:flutter_gopic/screens/configuration_screen.dart';
import 'package:flutter_gopic/services/history_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the clear upload history action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('gopic-config-test-');
    final history = HistoryService(cacheDirectoryResolver: () async => tempDir);
    await history.ready;
    addTearDown(() => tempDir.delete(recursive: true));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HistoryService>.value(value: history),
          ChangeNotifierProvider<CloudModel>.value(value: CloudModel()),
        ],
        child: const MaterialApp(home: Scaffold(body: ConfigurationScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('清除上传历史'), findsOneWidget);
  });
}
