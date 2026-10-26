import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/checksum.dart';
import '../../core/utils/lan_address.dart';
import '../../data/network/transfer_receiver.dart';
import '../../data/network/transfer_server.dart';
import '../../data/storage/storage_providers.dart';
import '../../domain/models/selected_file.dart';
import '../../domain/models/transfer_session.dart';

/// Sender-side debug state (Phase 2D). `preparing` (MVP 5 Phase 5A) is the
/// sha-256 hashing wait after file selection — previously a silent `busy`
/// wait that read as frozen on large files.
enum SenderPhase { idle, busy, preparing, ready, serving, completed, failed }

class SenderState {
  const SenderState({
    this.phase = SenderPhase.idle,
    this.fileName,
    this.fileSizeBytes,
    this.hashedBytes = 0,
    this.lanAddress,
    this.port,
    this.token,
    this.expiresAt,
    this.receiverConnected = false,
    this.error,
  });

  final SenderPhase phase;
  final String? fileName;
  final int? fileSizeBytes;

  /// Bytes already fed into the streaming sha-256 while [SenderPhase.preparing];
  /// drives the determinate "Preparing file…" progress against [fileSizeBytes].
  final int hashedBytes;

  /// What the receiver must enter: host, port, token.
  final InternetAddress? lanAddress;
  final int? port;
  final String? token;

  /// Session lifetime end for the UI countdown (MVP 3 Phase 3A).
  final DateTime? expiresAt;

  /// Monotonic while the session lives: the server never un-connects a
  /// receiver; only starting a new session clears it.
  final bool receiverConnected;
  final String? error;

  SenderState copyWith({
    SenderPhase? phase,
    String? fileName,
    int? fileSizeBytes,
    int? hashedBytes,
    InternetAddress? lanAddress,
    int? port,
    String? token,
    DateTime? expiresAt,
    bool receiverConnected = false,
    String? error,
    bool clearConnection = false,
    bool clearError = false,
  }) =>
      SenderState(
        phase: phase ?? this.phase,
        fileName: fileName ?? this.fileName,
        fileSizeBytes:
            clearConnection ? null : (fileSizeBytes ?? this.fileSizeBytes),
        hashedBytes: clearConnection ? 0 : (hashedBytes ?? this.hashedBytes),
        lanAddress: clearConnection ? null : (lanAddress ?? this.lanAddress),
        port: clearConnection ? null : (port ?? this.port),
        token: clearConnection ? null : (token ?? this.token),
        expiresAt: clearConnection ? null : (expiresAt ?? this.expiresAt),
        receiverConnected: clearConnection
            ? false
            : (receiverConnected || this.receiverConnected),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives the sender flow: pick file → session + server → track terminal state.
class SenderController extends Notifier<SenderState> {
  /// Hash-progress reporting granularity: state updates are throttled so
  /// per-chunk callbacks (64 KiB chunks on a multi-GB file) don't flood the UI.
  static const _hashReportInterval = 1 << 20;

  TransferServer? _server;
  Timer? _poll;
  SelectedFile? _selected;

  @override
  SenderState build() {
    ref.onDispose(_teardown);
    return const SenderState();
  }

  /// Picks a file and computes its REAL byte size + streamed sha-256 —
  /// string-length metadata breaks the HTTP Content-Length contract (2B lesson).
  /// The hashing pass is user-visible (`preparing`) with progress, not a
  /// silent wait (MVP 5 Phase 5A).
  Future<void> pickFile() async {
    state = const SenderState(phase: SenderPhase.busy);
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      final path = files.isEmpty ? null : files.first.path;
      if (path == null) {
        state = const SenderState();
        return;
      }
      final file = File(path);
      final total = await file.length();
      state = SenderState(
        phase: SenderPhase.preparing,
        fileName: files.first.name,
        fileSizeBytes: total,
      ).copyWith(clearConnection: true, clearError: true);
      final hash = ChecksumUtils.startStreaming();
      var hashed = 0;
      var lastReported = 0;
      await for (final chunk in file.openRead()) {
        hash.add(chunk);
        hashed += chunk.length;
        // Large files emit many small chunks; reporting every chunk would
        // flood the UI thread, so throttle to ~1 MiB granularity.
        if (hashed - lastReported >= _hashReportInterval) {
          lastReported = hashed;
          state = state.copyWith(hashedBytes: hashed);
        }
      }
      _selected = SelectedFile(
        name: files.first.name,
        path: path,
        sizeBytes: hashed,
        sha256: hash.finalize(),
      );
      state = SenderState(
        phase: SenderPhase.ready,
        fileName: files.first.name,
        fileSizeBytes: hashed,
      ).copyWith(clearConnection: true, clearError: true);
    } catch (e) {
      _selected = null;
      state = SenderState(error: 'Picking the file failed: $e');
    }
  }

  /// Test hook: FilePicker cannot open a dialog in tests, so tests inject
  /// the metadata that [pickFile] computes from real bytes.
  void injectFileForTest(SelectedFile selected) {
    _selected = selected;
    state = SenderState(
      phase: SenderPhase.ready,
      fileName: selected.name,
      fileSizeBytes: selected.sizeBytes,
    );
  }

  Future<void> startServing() async {
    final selected = _selected;
    if (selected == null || state.phase == SenderPhase.serving) return;
    state = state.copyWith(phase: SenderPhase.busy, clearError: true);
    try {
      final lan = await findLanAddress();
      if (lan == null) {
        state = state.copyWith(
          phase: SenderPhase.ready,
          error: 'No Wi-Fi/LAN address found — is the device connected '
              'to a Wi-Fi network?',
        );
        return;
      }
      final server = TransferServer(TransferSession.create(selected));
      await server.start();
      _server = server;
      _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final s = _server;
        if (s == null) return;
        if (!s.isRunning) {
          _poll?.cancel();
          _poll = null;
          final terminal = s.session.status;
          // Expired with no receiver is a sender-visible failure, not a
          // completed transfer (Phase 3C).
          final expired = terminal == TransferSessionStatus.expired;
          state = state.copyWith(
            phase: terminal == TransferSessionStatus.failed || expired
                ? SenderPhase.failed
                : SenderPhase.completed,
            error: expired
                ? 'The transfer session expired before a receiver connected.'
                : null,
            receiverConnected: s.receiverConnected,
          );
          return;
        }
        // Tick the connected flag every cycle so the UI rebuilds for the
        // countdown as well, not only on state transitions.
        state = state.copyWith(receiverConnected: s.receiverConnected);
      });
      state = state.copyWith(
        phase: SenderPhase.serving,
        lanAddress: lan,
        port: server.port,
        token: server.session.token,
        expiresAt: server.session.expiresAt,
      );
    } catch (e) {
      await _teardown();
      state =
          state.copyWith(phase: SenderPhase.ready, error: 'Start failed: $e');
    }
  }

  Future<void> stop() async {
    await _teardown();
    state = state.copyWith(
      phase: SenderPhase.ready,
      clearConnection: true,
      clearError: true,
    );
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> _teardown() async {
    _poll?.cancel();
    _poll = null;
    await _server?.stop();
    _server = null;
  }
}

/// Receiver-side state (MVP 3 Phase 3B).
class ReceiverState {
  const ReceiverState({
    this.busy = false,
    this.bytesReceived = 0,
    this.totalBytes = -1,
    this.speedBytesPerSec = 0,
    this.outcome,
    this.error,
  });

  final bool busy;

  /// Live download progress from the receiver engine; `totalBytes` is -1
  /// while unknown (no Content-Length / response not started).
  final int bytesReceived;
  final int totalBytes;

  /// Bytes per second over a small rolling window, derived in this state
  /// layer from consecutive progress events.
  final double speedBytesPerSec;

  /// Raw outcome of the last download attempt (success or typed failure).
  final DownloadOutcome? outcome;
  final String? error;

  ReceiverState copyWith({
    bool? busy,
    int? bytesReceived,
    int? totalBytes,
    double? speedBytesPerSec,
    DownloadOutcome? outcome,
    String? error,
    bool clearOutcome = false,
    bool clearError = false,
    bool clearProgress = false,
  }) =>
      ReceiverState(
        busy: busy ?? this.busy,
        bytesReceived: clearProgress ? 0 : (bytesReceived ?? this.bytesReceived),
        totalBytes: clearProgress ? -1 : (totalBytes ?? this.totalBytes),
        speedBytesPerSec:
            clearProgress ? 0 : (speedBytesPerSec ?? this.speedBytesPerSec),
        outcome: clearOutcome ? null : (outcome ?? this.outcome),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives the receiver flow: manual host/port/token entry → download with
/// live progress → cancel → result → retry / return-to-form (Phase 3C).
class ReceiverController extends Notifier<ReceiverState> {
  TransferCancelToken? _cancel;

  /// (time, cumulative bytes) samples for the rolling-window speed estimate.
  final List<MapEntry<DateTime, int>> _speedSamples = [];

  String? _lastHost;
  int? _lastPort;
  String? _lastToken;

  @override
  ReceiverState build() => const ReceiverState();

  void _onProgress(int bytesReceived, int totalBytes) {
    final now = DateTime.now();
    _speedSamples.add(MapEntry(now, bytesReceived));
    const window = Duration(seconds: 3);
    while (_speedSamples.length > 1 &&
        now.difference(_speedSamples.first.key) > window) {
      _speedSamples.removeAt(0);
    }
    var speed = 0.0;
    final first = _speedSamples.first;
    final elapsedMs = now.difference(first.key).inMilliseconds;
    if (_speedSamples.length >= 2 && elapsedMs > 0) {
      speed = (bytesReceived - first.value) / (elapsedMs / 1000);
    }
    state = state.copyWith(
      bytesReceived: bytesReceived,
      totalBytes: totalBytes,
      speedBytesPerSec: speed,
    );
  }

  Future<void> download(String host, String port, String token) async {
    final parsedPort = int.tryParse(port.trim());
    if (host.trim().isEmpty || parsedPort == null || parsedPort <= 0) {
      state = state.copyWith(error: 'Enter the sender IP, port, and token.');
      return;
    }
    _cancel = TransferCancelToken();
    _speedSamples.clear();
    _lastHost = host.trim();
    _lastPort = parsedPort;
    _lastToken = token.trim();
    state = const ReceiverState(busy: true);
    try {
      final outcome = await ref.read(transferReceiverProvider).download(
            host: host.trim(),
            port: parsedPort,
            token: token.trim(),
            onProgress: _onProgress,
            cancelToken: _cancel,
          );
      state = state.copyWith(
        busy: false,
        outcome: outcome,
        speedBytesPerSec: 0,
      );
    } catch (e) {
      state = ReceiverState(error: 'Unexpected error: $e');
    } finally {
      _cancel = null;
      _speedSamples.clear();
    }
  }

  void cancel() => _cancel?.cancel();

  /// Re-issues the last download with the same credentials (Phase 3C);
  /// silently ignored when no download was started from this controller.
  Future<void> retry() {
    final host = _lastHost;
    final port = _lastPort;
    final token = _lastToken;
    if (host == null || port == null || token == null) {
      return Future.value();
    }
    return download(host, '$port', token);
  }

  /// Return-to-start: clears the result so the connection form shows again.
  void reset() => state = const ReceiverState();

  void clearError() => state = state.copyWith(clearError: true);
}

final transferReceiverProvider = Provider<TransferReceiver>(
  (ref) => TransferReceiver(storage: ref.watch(storageRepositoryProvider)),
);

final senderControllerProvider =
    NotifierProvider<SenderController, SenderState>(SenderController.new);

final receiverControllerProvider =
    NotifierProvider<ReceiverController, ReceiverState>(ReceiverController.new);
