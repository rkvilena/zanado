import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/utils/bytes_format.dart';

void main() {
  test('formats sizes across unit boundaries', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(1024 * 1024), '1.0 MB');
    expect(formatBytes(3584 * 1024), '3.5 MB');
    expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    expect(formatBytes(1024 * 1024 * 1024 * 1024), '1.0 TB');
  });

  test('caps at the largest unit and handles negative input', () {
    expect(formatBytes(-1), '? B');
    final huge = 1024 * 1024 * 1024 * 1024 * 1024; // 1 PB — beyond TB
    expect(formatBytes(huge), endsWith('TB'));
  });
}
