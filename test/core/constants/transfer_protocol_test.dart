import 'package:flutter_test/flutter_test.dart';

import 'package:zanado/core/constants/transfer_protocol.dart';

void main() {
  group('TransferProtocol contract', () {
    test('file endpoint and auth header are stable names', () {
      expect(TransferProtocol.filePath, '/zanado/v1/file');
      expect(TransferProtocol.tokenHeader, 'X-Zanado-Token');
      expect(TransferProtocol.versionHeader, 'X-Zanado-Protocol');
      expect(TransferProtocol.checksumAlgorithm, 'sha-256');
    });

    test('error statuses cover the documented failure modes', () {
      expect(TransferProtocol.statusOk, 200);
      expect(TransferProtocol.statusBadRequest, 400);
      expect(TransferProtocol.statusUnauthorized, 401);
      expect(TransferProtocol.statusForbidden, 403);
      expect(TransferProtocol.statusNotFound, 404);
      expect(TransferProtocol.statusConflict, 409);
    });

    test('session bounds are sane', () {
      expect(
        TransferProtocol.minSessionDuration,
        lessThanOrEqualTo(TransferProtocol.defaultSessionDuration),
      );
      expect(
        TransferProtocol.defaultSessionDuration,
        lessThanOrEqualTo(TransferProtocol.maxSessionDuration),
      );
    });

    test('error codes round-trip through their wire names', () {
      for (final code in TransferErrorCode.values) {
        expect(TransferErrorCode.fromWireName(code.wireName), code);
      }
      expect(TransferErrorCode.fromWireName('nope'), isNull);
    });
  });
}