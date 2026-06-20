import 'package:flutter/services.dart';

class LaunchAtLoginService {
  LaunchAtLoginService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('gopic/launch-at-login');

  final MethodChannel _channel;

  Future<bool> isEnabled() async =>
      (await _channel.invokeMethod<bool>('isEnabled')) == true;

  Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setEnabled', enabled);
}
