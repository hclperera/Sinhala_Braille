import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../storage/scan_store.dart';
import 'saved_scans_screen.dart';
import 'sinhala_text.dart';
import '../recognition/recognizer.dart';
import '../speech/sinhala_speech.dart';
import 'capture_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();
  final _recognizer = LocalRecognizer();
  final _speech = SinhalaSpeech();
  bool _busy = false, _choosing = false;
  int _generation = 0;
  double _progress = 0;
  String _stage = '', _source = '';
  String? _error;
  ScanResult? _result;
  String _text = '';
  bool _saving = false, _saved = false;

  Future<ScanStore> _store() async {
    final root = await getApplicationSupportDirectory();
    return ScanStore(Directory('${root.path}/saved_scans'));
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _saving || _saved) return;
    setState(() => _saving = true);
    try {
      final store = await _store();
      await store.save(
        text: _text,
        originalText: result.text,
        warnings: result.warnings,
        seconds: result.seconds,
        dots: result.dots,
        slices: result.slices,
        imagePath: _source,
      );
      if (mounted) setState(() => _saved = true);
      _notice('Scan saved on this device');
    } catch (_) {
      _notice('Could not save the scan. Check available storage and retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSaved() async {
    await _speech.stop();
    try {
      final store = await _store();
      if (!mounted) return;
      final scan = await Navigator.of(context).push<SavedScan>(
        MaterialPageRoute(builder: (_) => SavedScansScreen(store: store)),
      );
      if (!mounted || scan == null) return;
      setState(() {
        _source = scan.imagePath;
        _text = scan.text;
        _saved = true;
        _error = null;
        _result = ScanResult(
          scan.originalText,
          scan.warnings,
          scan.imagePath,
          scan.seconds,
          scan.dots,
          scan.slices,
        );
      });
    } catch (_) {
      _notice('Could not open saved scans. Please retry.');
    }
  }

  Future<void> _edit() async {
    await _speech.stop();
    if (!mounted) return;
    final controller = TextEditingController(text: _text);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct Sinhala text'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            minLines: 5,
            maxLines: 12,
            style: sinhalaTextStyle,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Sinhala text',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    // The dialog route may still be animating with its text field attached.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (mounted && edited != null && edited != _text) {
      setState(() {
        _text = edited;
        _saved = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.addListener(_speechChanged);
    unawaited(_speech.initialize());
    _recoverSelection();
  }

  void _speechChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_speech.stop());
  }

  Future<void> _recoverSelection() async {
    if (!Platform.isAndroid) return;
    try {
      final response = await _picker.retrieveLostData();
      if (!mounted) return;
      if (_busy || _choosing || _source.isNotEmpty) return;
      if (response.files?.isNotEmpty == true) {
        await _scan(response.files!.first.path);
      } else if (response.exception != null) {
        setState(
          () => _error =
              'The image selection was interrupted. Please select it again.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Please select your image again.');
    }
  }

  Future<void> _choose({required bool camera}) async {
    if (_busy || _choosing) return;
    setState(() {
      _choosing = true;
      _error = null;
    });
    try {
      await _speech.stop();
      if (!mounted) return;
      String? path;
      if (camera) {
        path = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const CaptureScreen()),
        );
      } else {
        path = (await _picker.pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        ))?.path;
      }
      if (mounted && path != null) await _scan(path);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not open the image. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _scan(String path) async {
    await _speech.stop();
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _source = path;
      _error = null;
      _result = null;
      _progress = 0;
    });
    try {
      final result = await _recognizer.recognize(path, (stage, fraction) {
        if (mounted && generation == _generation) {
          setState(() {
            _stage = stage;
            _progress = fraction;
          });
        }
      });
      if (mounted && generation == _generation) {
        setState(() {
          _result = result;
          _text = result.text;
          _saved = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Recognition could not finish. Please retry.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _cancel() {
    _generation++;
    _recognizer.cancel();
    setState(() {
      _busy = false;
      _choosing = false;
      _stage = '';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speech.removeListener(_speechChanged);
    _speech.dispose();
    _generation++;
    _recognizer.cancel();
    super.dispose();
  }

  Widget _action(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? action,
  ) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF7B4FE0), size: 36),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF666071)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _busy) _cancel();
    },
    child: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
              decoration: const BoxDecoration(
                color: Color(0xFF7B4FE0),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(36),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'InfoX',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(Icons.wifi_off_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'OFFLINE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _result != null
                        ? 'Your Sinhala translation'
                        : 'Sinhala Braille reader',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Capture a page or select an image. Everything is processed on your device.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy) ...[
                    if (_source.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(
                          File(_source),
                          height: 220,
                          fit: BoxFit.contain,
                          cacheWidth: 800,
                          errorBuilder: (_, error, stackTrace) =>
                              const SizedBox(height: 80),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      _stage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 12),
                    const Text(
                      'Full pages may take a while. Keep the app open.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _cancel,
                      child: const Text('Cancel'),
                    ),
                  ] else ...[
                    if (_error != null) ...[
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    OutlinedButton.icon(
                      onPressed: _choosing || _saving ? null : _openSaved,
                      icon: const Icon(Icons.bookmarks_outlined),
                      label: const Text('Saved scans'),
                    ),
                    const SizedBox(height: 12),
                    if (_result case final result?) ...[
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _saving || _saved ? null : _save,
                            icon: Icon(
                              _saved
                                  ? Icons.check
                                  : Icons.bookmark_add_outlined,
                            ),
                            label: Text(
                              _saving
                                  ? 'Saving…'
                                  : _saved
                                  ? 'Saved'
                                  : 'Save scan',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _edit,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Correct text'),
                          ),
                        ],
                      ),
                      if (_text.contains('\uFFFD'))
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '� marks a Braille cell that could not be read. '
                            'Check the photo or use Correct text. These are recognition uncertainties.',
                          ),
                        ),

                      Card(
                        color: Colors.white,
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SinhalaText(_text),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _speech.available && !_speech.isChecking
                            ? () {
                                if (_speech.isSpeaking) {
                                  unawaited(_speech.stop());
                                } else {
                                  unawaited(_speech.play(_text));
                                }
                              }
                            : null,
                        icon: Icon(
                          _speech.isSpeaking
                              ? Icons.stop
                              : Icons.volume_up_outlined,
                        ),
                        label: Text(
                          _speech.isChecking
                              ? 'Checking offline voice…'
                              : _speech.isSpeaking
                              ? 'Stop reading'
                              : 'Play Sinhala text',
                        ),
                      ),
                      if (_speech.notice != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _speech.notice!,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (!_speech.available && !_speech.isChecking)
                        TextButton(
                          onPressed: () => unawaited(_speech.refresh()),
                          child: const Text('Check offline voice again'),
                        ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _text.trim()),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Translation copied'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy Sinhala text'),
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        title: const Text('Scan photo'),
                        children: [
                          Image.file(
                            File(_source),
                            height: 260,
                            fit: BoxFit.contain,
                            cacheWidth: 1000,
                            errorBuilder: (_, error, stack) => const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('The photo is no longer available.'),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${result.dots} front dots · ${result.slices} sections · ${result.seconds.toStringAsFixed(1)} seconds',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (result.warnings.isNotEmpty)
                        ExpansionTile(
                          title: const Text('Recognition notes'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                result.warnings.join('\n'),
                                style: const TextStyle(height: 1.6),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                    ],
                    _action(
                      'Capture a page',
                      'Manual capture with the flashlight on',
                      Icons.camera_alt_outlined,
                      _choosing || _saving ? null : () => _choose(camera: true),
                    ),
                    const SizedBox(height: 12),
                    _action(
                      'Select an image',
                      'Choose an existing photo from your device',
                      Icons.photo_library_outlined,
                      _choosing || _saving
                          ? null
                          : () => _choose(camera: false),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'No account or internet connection required.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF666071)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
