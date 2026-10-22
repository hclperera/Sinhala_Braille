import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void> _operations = Future.value();
  bool _wanted = true, _ready = false, _capturing = false, _torch = false;
  bool _finishing = false;
  bool _focusing = false;
  Offset? _focusPoint;
  Timer? _focusTimer;
  String? _focusNotice;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enqueue(_syncCamera);
  }

  void _enqueue(Future<void> Function() operation) {
    _operations = _operations.then((_) => operation()).catchError((
      Object error,
    ) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _ready = false;
          _capturing = false;
        });
      }
    });
  }

  String _message(Object error) {
    if (error is CameraException) {
      if (error.code.contains('AccessDenied') ||
          error.code.contains('AccessRestricted')) {
        return 'Camera permission is required. Enable camera access in your phone settings, then retry.';
      }
      return error.description ?? error.code;
    }
    return 'Could not open the camera. Please retry.';
  }

  Future<void> _release() async {
    _focusTimer?.cancel();
    final controller = _controller;
    final hadPreview = _ready;
    if (mounted) {
      setState(() {
        _controller = null;
        _ready = false;
        _focusing = false;
        _focusPoint = null;
      });
      // CameraPreview listens to the controller. Unmount it before flash mode
      // changes/disposal can notify it during the capture-to-result transition.
      // Backgrounded apps cannot produce frames, so release immediately there.
      if (hadPreview &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        await WidgetsBinding.instance.endOfFrame;
      }
    } else {
      _controller = null;
      _ready = false;
      _focusing = false;
      _focusPoint = null;
    }
    if (controller != null) {
      try {
        if (controller.value.isInitialized) {
          await controller.setFlashMode(FlashMode.off);
        }
      } on CameraException {
        /* Disposing also releases an interrupted camera. */
      } finally {
        await controller.dispose();
      }
    }
  }

  Future<void> _syncCamera() async {
    if (!_wanted || !mounted) {
      await _release();
      return;
    }
    if (_controller?.value.isInitialized == true) return;
    if (mounted) {
      setState(() {
        _error = null;
        _ready = false;
      });
    }
    try {
      final cameras = await availableCameras();
      if (!_wanted || !mounted) return;
      final rear = cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();
      if (rear.isEmpty) {
        throw CameraException(
          'NoCamera',
          'No rear camera is available. Select an existing image instead.',
        );
      }
      final controller = CameraController(
        rear.first,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
      if (!_wanted || !mounted) {
        await _release();
        return;
      }
      var torch = false;
      try {
        await controller.setFlashMode(FlashMode.torch);
        torch = true;
      } on CameraException {
        /* Some cameras do not have an available torch. */
      }
      try {
        await controller.setFocusMode(FocusMode.auto);
      } on CameraException {
        // Fixed-focus cameras must remain usable for manual capture.
      }
      if (!_wanted || !mounted) {
        await _release();
        return;
      }
      setState(() {
        _ready = true;
        _torch = torch;
        _focusNotice = null;
      });
    } catch (error) {
      await _release();
      if (mounted && _wanted) setState(() => _error = _message(error));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _wanted = !_finishing && state == AppLifecycleState.resumed;
    if (!_wanted && mounted) setState(() => _ready = false);
    _enqueue(_syncCamera);
  }

  void _capture() {
    if (!_ready || _capturing || _focusing) return;
    setState(() => _capturing = true);
    _enqueue(() async {
      final controller = _controller;
      if (controller == null || !_wanted) {
        if (mounted) setState(() => _capturing = false);
        return;
      }
      try {
        // The continuous torch stays enabled until takePicture completes.
        final image = await controller.takePicture();
        _finishing = true;
        _wanted = false;
        await _release();
        if (mounted) Navigator.pop(context, image.path);
      } catch (error) {
        if (mounted) {
          setState(() {
            _finishing = false;
            _wanted =
                WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed;
            _capturing = false;
            _error = _message(error);
          });
        }
      }
    });
  }

  void _focus(Offset? point) {
    final controller = _controller;
    if (!_ready || _capturing || _focusing || controller == null) return;
    if (!controller.value.focusPointSupported) {
      setState(
        () => _focusNotice = 'Tap-to-focus is unavailable on this camera.',
      );
      return;
    }
    _focusTimer?.cancel();
    setState(() {
      _focusing = true;
      _focusPoint = point;
      _focusNotice = null;
    });
    // Serialize focus requests with capture, backgrounding and camera disposal.
    _enqueue(() async {
      try {
        if (!mounted || !_wanted || controller != _controller) return;
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(point);
      } on CameraException {
        if (mounted && _wanted && controller == _controller) {
          setState(() {
            _focusPoint = null;
            _focusNotice = 'Could not adjust focus. Try tapping again.';
          });
        }
      } finally {
        if (mounted && controller == _controller) {
          setState(() => _focusing = false);
          _focusTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) setState(() => _focusPoint = null);
          });
        }
      }
    });
  }

  Widget _preview(CameraController controller) => CameraPreview(
    controller,
    // This overlay has exactly the preview's aspect ratio, so taps in the
    // surrounding letterbox never become inaccurate camera coordinates.
    child: LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _capturing || _focusing
              ? null
              : (details) {
                  if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                    return;
                  }
                  _focus(
                    Offset(
                      (details.localPosition.dx / constraints.maxWidth).clamp(
                        0.0,
                        1.0,
                      ),
                      (details.localPosition.dy / constraints.maxHeight).clamp(
                        0.0,
                        1.0,
                      ),
                    ),
                  );
                },
          child: Stack(
            children: [
              if (_focusPoint case final point?)
                Positioned(
                  left: point.dx * constraints.maxWidth - 28,
                  top: point.dy * constraints.maxHeight - 28,
                  child: IgnorePointer(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.amberAccent, width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  @override
  void dispose() {
    _focusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _wanted = false;
    _enqueue(_release);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_capturing,
    child: Scaffold(
      backgroundColor: const Color(0xFF0C031F),
      appBar: AppBar(title: const Text('Capture a page')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => _enqueue(() async {
                                await _release();
                                await _syncCamera();
                              }),
                              child: const Text('Retry camera'),
                            ),
                          ],
                        ),
                      )
                    : !_ready || _controller == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : _preview(_controller!),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                children: [
                  Text(
                    _ready
                        ? (_torch
                              ? 'Flashlight on'
                              : 'Flashlight unavailable on this camera')
                        : _finishing
                        ? 'Preparing image…'
                        : 'Preparing camera',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  if (_ready) ...[
                    Text(
                      _focusNotice ??
                          (_focusing
                              ? 'Adjusting focus…'
                              : _controller?.value.focusPointSupported == true
                              ? 'Tap the page to focus'
                              : 'Focus is managed by this camera'),
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    if (_controller?.value.focusPointSupported == true)
                      TextButton.icon(
                        onPressed: _capturing || _focusing
                            ? null
                            : () => _focus(null),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.center_focus_strong),
                        label: const Text('Reset autofocus'),
                      ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _ready && !_capturing && !_focusing
                          ? _capture
                          : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(_capturing ? 'Capturing…' : 'Capture image'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
