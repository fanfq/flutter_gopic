import 'dart:math';

import '../models/cloud_model.dart';

class ObjectNameGenerator {
  ObjectNameGenerator({
    DateTime Function()? clock,
    String Function()? hashFactory,
    String Function()? uuidFactory,
  }) : _clock = clock ?? DateTime.now,
       _hashFactory = hashFactory ?? _newHash,
       _uuidFactory = uuidFactory ?? _newUuid;

  final DateTime Function() _clock;
  final String Function() _hashFactory;
  final String Function() _uuidFactory;

  String build({
    required UploadNamingPattern pattern,
    required String fileName,
  }) {
    final date = _datePart(_clock());
    return switch (pattern) {
      UploadNamingPattern.datedHashFileName =>
        '$date/${_hashFactory()}_${_safeName(fileName)}',
      UploadNamingPattern.datedUuid =>
        '$date/${_uuidFactory()}${_extension(fileName)}',
      UploadNamingPattern.uuid => '${_uuidFactory()}${_extension(fileName)}',
    };
  }

  static String _datePart(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^\w.\-]+'), '_');

  static String _extension(String fileName) {
    final name = fileName.split(RegExp(r'[/\\]')).last;
    final index = name.lastIndexOf('.');
    return index <= 0 ? '' : name.substring(index);
  }

  static String _newHash() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      List.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
