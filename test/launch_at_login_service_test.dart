import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gopic/services/launch_at_login_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('gopic/launch-at-login');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('reads and updates the macOS launch-at-login state', (
    tester,
  ) async {
    final calls = <String>[];
    var enabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isEnabled') {
            calls.add('isEnabled');
            return enabled;
          }
          if (call.method == 'setEnabled') {
            enabled = call.arguments as bool;
            calls.add('setEnabled:$enabled');
            return null;
          }
          throw MissingPluginException();
        });

    final service = LaunchAtLoginService(channel: channel);

    expect(await service.isEnabled(), isFalse);
    await service.setEnabled(true);
    expect(calls, ['isEnabled', 'setEnabled:true']);
  });
}
