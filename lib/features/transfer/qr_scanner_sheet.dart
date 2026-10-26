import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Signature for the camera surface of [QrScannerSheet]. Production wires the
/// real [MobileScanner]; widget tests inject a fake detector so no camera
/// plugin is touched.
typedef QrCameraBuilder = Widget Function(
  BuildContext context,
  void Function(String raw) onCodeScanned,
);

/// Overridable camera surface. Tests inject a fake detector so no camera
/// plugin is touched; production stays null (real [MobileScanner]).
final qrCameraBuilderProvider =
    Provider<QrCameraBuilder?>((ref) => null);

Future<void> showQrScannerSheet(
  BuildContext context, {
  required ValueChanged<String> onCodeScanned,
  QrCameraBuilder? cameraBuilder,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => QrScannerSheet(
      onCodeScanned: onCodeScanned,
      cameraBuilder: cameraBuilder,
    ),
  );
}

class QrScannerSheet extends StatefulWidget {
  const QrScannerSheet({
    super.key,
    required this.onCodeScanned,
    this.cameraBuilder,
  });

  final ValueChanged<String> onCodeScanned;

  /// Defaults to the real camera; only tests supply a replacement.
  final QrCameraBuilder? cameraBuilder;

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet> {
  // A scan fires continuously while the code is in view; without this guard
  // the first hit would be processed many times before the sheet pops.
  var _handled = false;
  MobileScannerController? _cameraController;

  @override
  void initState() {
    super.initState();
    if (widget.cameraBuilder == null) {
      _cameraController = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  void _handleScan(String raw) {
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context).pop();
    widget.onCodeScanned(raw);
  }

  Widget _camera(BuildContext context) {
    final builder = widget.cameraBuilder;
    if (builder != null) return builder(context, _handleScan);
    return MobileScanner(
      controller: _cameraController,
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw != null) _handleScan(raw);
      },
      errorBuilder: (context, error) => const _CameraError(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Point the camera at the sender\u2019s QR code',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _camera(context),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Enter manually'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Camera unavailable. Grant camera access or enter the code manually.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
