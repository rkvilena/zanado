import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/constants/transfer_protocol.dart';
import 'package:zanado/core/utils/token.dart';
import 'package:zanado/domain/models/selected_file.dart';
import 'package:zanado/domain/models/transfer_session.dart';

final _sha = 'a' * 64;

SelectedFile _file() => SelectedFile(
      name: 'video.mp4',
      path: '/tmp/video.mp4',
      sizeBytes: 1024,
      sha256: _sha,
    );

void main() {
  group('TransferSession.create', () {
    test('generates a valid token and default expiry', () {
      final now = DateTime(2026, 10, 25, 12);
      final session = TransferSession.create(_file(), now: now);
      expect(TransferToken.isValidFormat(session.token), isTrue);
      expect(session.createdAt, now);
      expect(
        session.expiresAt,
        now.add(TransferProtocol.defaultSessionDuration),
      );
      expect(session.status, TransferSessionStatus.active);
      expect(session.isDownloadable, isTrue);
    });

    test('clamps too-short lifetimes to the minimum', () {
      final now = DateTime(2026, 10, 25, 12);
      final session = TransferSession.create(_file(), now: now, duration: const Duration(seconds: 1));
      expect(session.expiresAt.difference(session.createdAt),
          TransferProtocol.minSessionDuration);
    });

    test('clamps too-long lifetimes to the maximum', () {
      final now = DateTime(2026, 10, 25, 12);
      final session = TransferSession.create(
        _file(),
        now: now,
        duration: const Duration(days: 365),
      );
      expect(session.expiresAt.difference(session.createdAt),
          TransferProtocol.maxSessionDuration);
    });
  });

  group('TransferSession construction guards', () {
    test('rejects invalid file metadata', () {
      final bad = SelectedFile(name: '', path: '/x', sizeBytes: 1, sha256: _sha);
      expect(() => TransferSession.create(bad), throwsArgumentError);
    });

    test('rejects malformed tokens', () {
      expect(
        () => TransferSession(
          selectedFile: _file(),
          token: 'nope',
          createdAt: DateTime(2026),
          expiresAt: DateTime(2026, 1, 2),
        ),
        throwsArgumentError,
      );
    });

    test('rejects expiry before creation', () {
      expect(
        () => TransferSession(
          selectedFile: _file(),
          token: TransferToken.generate(),
          createdAt: DateTime(2026, 1, 2),
          expiresAt: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('TransferSession lifecycle', () {
    final now = DateTime(2026, 10, 25, 12);
    late TransferSession session;
    setUp(() => session = TransferSession.create(_file(), now: now));

    test('is not expired before expiry time', () {
      expect(session.isExpiredAt(now.add(const Duration(minutes: 9))), isFalse);
    });

    test('is expired after expiry time', () {
      expect(session.isExpiredAt(session.expiresAt), isFalse); // boundary inclusive
      expect(session.isExpiredAt(session.expiresAt.add(const Duration(seconds: 1))), isTrue);
    });

    test('expireIfPast marks active sessions past their expiry', () {
      final future = session.expiresAt.add(const Duration(seconds: 1));
      final expired = session.expireIfPast(future);
      expect(expired.status, TransferSessionStatus.expired);
      expect(expired.isDownloadable, isFalse);
    });

    test('expireIfPast is a no-op before expiry and on terminal sessions', () {
      expect(session.expireIfPast(now).status, TransferSessionStatus.active);
      final cancelled = session.markCancelled();
      expect(
        cancelled
            .expireIfPast(session.expiresAt.add(const Duration(hours: 1)))
            .status,
        TransferSessionStatus.cancelled,
      );
    });

    test('terminal transitions disable downloading and preserve identity', () {
      final completed = session.markCompleted();
      expect(completed.isDownloadable, isFalse);
      expect(completed.token, session.token);
      expect(completed.selectedFile, session.selectedFile);
      expect(session.markFailed().isDownloadable, isFalse);
      expect(session.markCancelled().isDownloadable, isFalse);
      // Original remains active: sessions are immutable, transitions copy.
      expect(session.isDownloadable, isTrue);
    });
  });
}