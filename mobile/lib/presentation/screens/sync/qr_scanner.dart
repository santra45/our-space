import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';

abstract final class QrScannerCopy {
  static const String title = 'Scan Partner\'s QR';
  static const String subtitle = 'Point your camera at their screen to pair';
  static const String cameraError = 'Camera permission denied or camera not available.';
  static const String footer = 'Scanning stays on this device. Nothing is uploaded.';
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
  return showOurModal<String>(
    context: context,
    backdrop: OurBackdropTone.black80,
    entrance: OurModalEntrance.popSoft,
    builder: (_) => const QrScannerModal(),
  );
}

class QrScannerModal extends StatefulWidget {
  const QrScannerModal({super.key});

  @override
  State<QrScannerModal> createState() => _QrScannerModalState();
}

class _QrScannerModalState extends State<QrScannerModal> {
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
    final radius = AppRadii.all(AppRadii.x3l);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthSm),
      child: Material(
        type: MaterialType.transparency,
        child: CssBox(
          color: AppColors.slate900,
          borderRadius: radius,
          clipContent: true,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(QrScannerCopy.title, textAlign: TextAlign.center, style: Tw.base.bold.c(AppColors.white)),
                    Text(QrScannerCopy.subtitle, textAlign: TextAlign.center, style: Tw.xs.c(AppColors.slate400)),
                    const SizedBox(height: 16),
                    if (_cameraError)
                      CssBox(
                        padding: const EdgeInsets.all(16),
                        color: AppColors.rose500.withValues(alpha: 0.2),
                        border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
                        borderRadius: AppRadii.all(AppRadii.x2l),
                        child: Text(
                          QrScannerCopy.cameraError,
                          textAlign: TextAlign.center,
                          style: Tw.xs.c(AppColors.rose300),
                        ),
                      )
                    else
                      AspectRatio(
                        aspectRatio: 1,
                        child: CssBox(
                          color: AppColors.black,
                          border: Border.all(color: AppColors.blush400, width: 2),
                          borderRadius: AppRadii.all(AppRadii.x2l),
                          child: ClipRRect(
                            borderRadius: AppRadii.all(AppRadii.x2l - 2),
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
                                    child: TwPulse(
                                      child: CssBox(
                                        dashedBorder: BorderSide(
                                          color: AppColors.white.withValues(alpha: 0.6),
                                          width: 2,
                                        ),
                                        borderRadius: AppRadii.all(AppRadii.x2l),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      QrScannerCopy.footer,
                      textAlign: TextAlign.center,
                      style: Tw.px10.relaxed.c(AppColors.slate500),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: OurCloseButton(
                  onPressed: _close,
                  background: AppColors.white.withValues(alpha: 0.2),
                  foreground: AppColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      errorBuilder: (context, error, child) => const ColoredBox(color: AppColors.black),
      placeholderBuilder: (context, child) => const ColoredBox(color: AppColors.black),
    );
  }
}
