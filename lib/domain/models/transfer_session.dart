import '../../core/constants/transfer_protocol.dart';
import '../../core/utils/token.dart';
import 'selected_file.dart';

/// Lifecycle of a transfer session as seen by the sender.
enum TransferSessionStatus { active, completed, failed, expired, cancelled }

/// An authenticated, short-lived offer to download one file.
///
/// Pure domain object: the sender server hosts it, the receiver
/// learns about it through the pairing payload (host/port/token), and every
/// request must present [token] in the [TransferProtocol.tokenHeader].
class TransferSession {
  TransferSession({
    required this.selectedFile,
    required this.token,
    required this.createdAt,
    required this.expiresAt,
    this.status = TransferSessionStatus.active,
  }) {
    if (!selectedFile.isValid) {
      throw ArgumentError('SelectedFile metadata is invalid');
    }
    if (!TransferToken.isValidFormat(token)) {
      throw ArgumentError('Session token has an invalid format');
    }
    if (expiresAt.isBefore(createdAt)) {
      throw ArgumentError('expiresAt must not be before createdAt');
    }
  }

  /// Creates a session with the lifetime clamped into
  /// [TransferProtocol.minSessionDuration]..[TransferProtocol.maxSessionDuration].
  /// Clamping keeps a hostile payload from minting a near-permanent token.
  factory TransferSession.create(
    SelectedFile file, {
    DateTime? now,
    Duration duration = TransferProtocol.defaultSessionDuration,
  }) {
    final created = now ?? DateTime.now();
    final clamped = duration < TransferProtocol.minSessionDuration
        ? TransferProtocol.minSessionDuration
        : (duration > TransferProtocol.maxSessionDuration
            ? TransferProtocol.maxSessionDuration
            : duration);
    return TransferSession(
      selectedFile: file,
      token: TransferToken.generate(),
      createdAt: created,
      expiresAt: created.add(clamped),
    );
  }

  final SelectedFile selectedFile;
  final String token;
  final DateTime createdAt;
  final DateTime expiresAt;
  final TransferSessionStatus status;

  bool isExpiredAt(DateTime time) => time.isAfter(expiresAt);

  /// A session only accepts downloads while active and unexpired. Terminal
  /// statuses (completed/failed/cancelled/expired) reject further requests.
  bool get isDownloadable => status == TransferSessionStatus.active;

  TransferSession markCompleted() => _copy(TransferSessionStatus.completed);
  TransferSession markFailed() => _copy(TransferSessionStatus.failed);
  TransferSession markCancelled() => _copy(TransferSessionStatus.cancelled);

  /// Marks a still-active session as expired. Returns `this` unchanged when
  /// the session is already in a terminal state (immutability contract).
  TransferSession expireIfPast(DateTime time) =>
      isExpiredAt(time) && status == TransferSessionStatus.active
          ? _copy(TransferSessionStatus.expired)
          : this;

  TransferSession _copy(TransferSessionStatus status) => TransferSession(
        selectedFile: selectedFile,
        token: token,
        createdAt: createdAt,
        expiresAt: expiresAt,
        status: status,
      );

  @override
  String toString() =>
      'TransferSession(${selectedFile.name}, status: $status, '
      'expires: $expiresAt)';
}