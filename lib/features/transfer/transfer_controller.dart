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

/// Sender-side debug state (Phase 2D).
enum SenderPhase { idle, busy, ready, serving, completed, failed }

class SenderState {
  const SenderState({
    this.phase = SenderPhase.idle,
    this.fileName,
    this.lanAddress,
    this.port,
    this.token,
    this.error,
  });

  final SenderPhase phase;
  final String? fileName;

  /// What the receiver must enter: host, port, token.
  final InternetAddress? lanAddress;
  final int? port;
  final String? token;
  final String? error;

  SenderState copyWith({
    SenderPhase? phase,
    String? fileName,
    InternetAddress? lanAddress,
    int? port,
    String? token,
    String? error,
    bool clearConnection = false,
    bool clearError = false,
  }) =>
      SenderState(
        phase: phase ?? this.phase,
        fileName: fileName ?? this.fileName,
        lanAddress: clearConnection ? null : (lanAddress ?? this.lanAddress),
        port: clearConnection ? null : (port ?? this.port),
        token: clearConnection ? null : (token ?? this.token),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives the sender flow: pick file → session + server → track terminal state.
class SenderController extends Notifier<SenderState> {
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
      final hash = ChecksumUtils.startStreaming();
      var size = 0;
      await for (final chunk in file.openRead()) {
        hash.add(chunk);
        size += chunk.length;
      }
      _selected = SelectedFile(
        name: files.first.name,
        path: path,
        sizeBytes: size,
        sha256: hash.finalize(),
      );
      state = SenderState(phase: SenderPhase.ready, fileName: files.first.name)
          .copyWith(clearConnection: true, clearError: true);
    } catch (e) {
      _selected = null;
      state = SenderState(error: 'Picking the file failed: $e');
    }
  }

  /// Test hook: FilePicker cannot open a dialog in tests, so tests inject
  /// the metadata that [pickFile] computes from real bytes.
  void injectFileForTest(SelectedFile selected) {
    _selected = selected;
    state = SenderState(phase: SenderPhase.ready, fileName: selected.name);
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
        if (s == null || !s.isRunning) {
          _poll?.cancel();
          _poll = null;
          final terminal = s?.session.status;
          state = state.copyWith(
            phase: terminal == TransferSessionStatus.failed
                ? SenderPhase.failed
                : SenderPhase.completed,
          );
        }
      });
      state = state.copyWith(
        phase: SenderPhase.serving,
        lanAddress: lan,
        port: server.port,
        token: server.session.token,
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

/// Receiver-side debug state (Phase 2D).
class ReceiverState {
  const ReceiverState({this.busy = false, this.outcome, this.error});

  final bool busy;

  /// Raw outcome of the last download attempt (success or typed failure).
  final DownloadOutcome? outcome;
  final String? error;

  ReceiverState copyWith({
    bool? busy,
    DownloadOutcome? outcome,
    String? error,
    bool clearOutcome = false,
    bool clearError = false,
  }) =>
      ReceiverState(
        busy: busy ?? this.busy,
        outcome: clearOutcome ? null : (outcome ?? this.outcome),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives the receiver flow: manual host/port/token entry → download → result.
class ReceiverController extends Notifier<ReceiverState> {
  @override
  ReceiverState build() => const ReceiverState();

  Future<void> download(String host, String port, String token) async {
    final parsedPort = int.tryParse(port.trim());
    if (host.trim().isEmpty || parsedPort == null || parsedPort <= 0) {
      state = state.copyWith(error: 'Enter the sender IP, port, and token.');
      return;
    }
    state = state.copyWith(busy: true, clearOutcome: true, clearError: true);
    try {
      final outcome = await ref.read(transferReceiverProvider).download(
            host: host.trim(),
            port: parsedPort,
            token: token.trim(),
          );
      state = ReceiverState(outcome: outcome);
    } catch (e) {
      state = ReceiverState(error: 'Unexpected error: $e');
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final transferReceiverProvider = Provider<TransferReceiver>(
  (ref) => TransferReceiver(storage: ref.watch(storageRepositoryProvider)),
);

final senderControllerProvider =
    NotifierProvider<SenderController, SenderState>(SenderController.new);

final receiverControllerProvider =
    NotifierProvider<ReceiverController, ReceiverState>(ReceiverController.new);
