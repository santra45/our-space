import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../settings/widgets/sheet_parts.dart';

abstract final class QrScannerCopy {
  static const String title = 'Scan their code';
  static const String subtitle = 'Point your camera at the code on their screen';
  static const String cameraError = 'We could not use the camera. Check that Our Space may use it, then try again.';
  static const String footer = 'What the camera sees stays on this phone.';
}

@immutable
class QrCameraHandlers {
  const QrCameraHandlers({required this.onCode, required this.onError});

  final ValueChanged<String> onCode;
  final VoidCallback onError;
}

typedef QrCameraBuilder = Widget Function(BuildContext context, QrCameraHandlers handlers);

abstract final class QrCamera {
  static QrCameraBuilder builder = _deviceCamera;

  static Widget _deviceCamera(BuildContext context, QrCameraHandlers handlers) => DeviceQrCamera(handlers: handlers);
}

String? acceptScannedInvite(String? raw) {
  final payload = raw?.trim() ?? '';
  if (payload.isEmpty) return null;
  return parseInvite(payload) == null ? null : payload;
}

Future<String?> showQrScanner(BuildContext context) {
  return showSkySheet<String>(context: context, builder: (_) => const QrScannerSheet());
}

class QrScannerSheet extends StatefulWidget {
  const QrScannerSheet({super.key});

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet> {
  bool _cameraError = false;
  bool _done = false;

  late final QrCameraHandlers _handlers = QrCameraHandlers(onCode: _onCode, onError: _onError);

  void _onCode(String raw) {
    if (_done || !mounted) return;
    final payload = acceptScannedInvite(raw);
    if (payload == null) return;
    _done = true;
    AppHaptics.celebration();
    Navigator.of(context).pop(payload);
  }

  void _onError() {
    if (!mounted || _cameraError) return;
    setState(() => _cameraError = true);
  }

  void _close() {
    AppHaptics.tap();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final window = _cameraError
        ? const SkyNotice(
            key: ValueKey<String>('scanner-error'),
            text: QrScannerCopy.cameraError,
            tone: SkyNoticeTone.error,
            icon: SkyIcons.camera,
          )
        : Center(
            key: const ValueKey<String>('scanner-camera'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF05040F),
                    borderRadius: SkyRadii.all(SkyRadii.feature),
                    border: Border.all(color: t.rose, width: 2),
                    boxShadow: [BoxShadow(color: t.rose.withValues(alpha: t.isNight ? 0.35 : 0.22), blurRadius: 24)],
                  ),
                  child: ClipRRect(
                    borderRadius: SkyRadii.all(SkyRadii.feature - 2),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        QrCamera.builder(context, _handlers),
                        Positioned.fill(
                          left: 32,
                          top: 32,
                          right: 32,
                          bottom: 32,
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: SkyPulse(
                                minScale: 0.97,
                                maxScale: 1,
                                child: CustomPaint(painter: ScanFramePainter(color: t.gold)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
    return SheetScroll(
      children: [
        SheetHeader(
          title: QrScannerCopy.title,
          subtitle: QrScannerCopy.subtitle,
          icon: SkyIcons.scan,
          tone: SkyTone.rose,
          onClose: _close,
        ),
        window,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkyIcon(SkyIcons.lock, size: 12, color: t.faint),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                QrScannerCopy.footer,
                textAlign: TextAlign.center,
                style: SkyType.caption.copyWith(color: t.faint),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ScanFramePainter extends CustomPainter {
  const ScanFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final arm = size.shortestSide * 0.18;
    const r = 14.0;
    final w = size.width;
    final h = size.height;
    final corners = [
      Path()
        ..moveTo(0, arm)
        ..lineTo(0, r)
        ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
        ..lineTo(arm, 0),
      Path()
        ..moveTo(w - arm, 0)
        ..lineTo(w - r, 0)
        ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
        ..lineTo(w, arm),
      Path()
        ..moveTo(w, h - arm)
        ..lineTo(w, h - r)
        ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r))
        ..lineTo(w - arm, h),
      Path()
        ..moveTo(arm, h)
        ..lineTo(r, h)
        ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))
        ..lineTo(0, h - arm),
    ];
    for (final corner in corners) {
      canvas.drawPath(corner, paint);
    }
  }

  @override
  bool shouldRepaint(ScanFramePainter oldDelegate) => oldDelegate.color != color;
}

class DeviceQrCamera extends StatefulWidget {
  const DeviceQrCamera({super.key, required this.handlers});

  final QrCameraHandlers handlers;

  @override
  State<DeviceQrCamera> createState() => _DeviceQrCameraState();
}

class _DeviceQrCameraState extends State<DeviceQrCamera> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.start().catchError((Object _) {}));
      case AppLifecycleState.inactive:
        unawaited(_controller.stop().catchError((Object _) {}));
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        break;
    }
  }

  void _onState() {
    if (_controller.value.error != null) widget.handlers.onError();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null) widget.handlers.onCode(raw);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onState);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      fit: BoxFit.cover,
      onDetect: _onDetect,
      errorBuilder: (context, error, child) => const ColoredBox(color: Color(0xFF000000)),
      placeholderBuilder: (context, child) => const ColoredBox(color: Color(0xFF000000)),
    );
  }
}
