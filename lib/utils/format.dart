/// Human-readable byte size, e.g. `formatBytes(1536) => "1.5 KB"`.
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (bytes.bitLength - 1) ~/ 10; // log2(bytes)/10
  final idx = i < units.length ? i : units.length - 1;
  final size = bytes / (1 << (idx * 10));
  return '${size.toStringAsFixed(idx == 0 ? 0 : decimals)} ${units[idx]}';
}

/// Short date like `2026-06-16 14:08`.
String formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
