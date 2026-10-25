/// Formats a byte count as a human-readable size for transfer UI, e.g.
/// `512 B`, `3.4 MB`, `1.2 GB`.
String formatBytes(int bytes) {
  if (bytes < 0) return '? B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(value >= 100 ? 0 : 1);
  return '$text ${units[unit]}';
}
