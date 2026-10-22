import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'speech_policy.dart';

class SinhalaSpeech extends ChangeNotifier {
  SinhalaSpeech({FlutterTts? engine}) : _tts = engine ?? FlutterTts() {
    _tts.setErrorHandler((message) {
      if (_disposed) return;
      _generation++;
      isSpeaking = false;
      notice =
          'Speech could not finish. Check that your Sinhala voice is installed for offline use.';
      notifyListeners();
    });
  }
  final FlutterTts _tts;
  Future<void>? _initialization;
  bool _disposed = false;
  int _generation = 0;
  bool isSpeaking = false, isChecking = false, available = false;
  String? notice;
  Map<String, String>? _voice;
  Future<void> initialize() => _initialization ??= _configure();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _configure() async {
    isChecking = true;
    available = false;
    notice = null;
    _notify();
    try {
      final voices = await _tts.getVoices;
      if (_disposed) return;
      _voice = offlineSinhalaVoice(
        voices is List ? voices : [],
        android: Platform.isAndroid,
      );
      if (_voice == null) {
        notice =
            'No installed offline Sinhala voice was found. Add one in your device’s text-to-speech settings, then check again.';
        return;
      }
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(.45);
      await _tts.setVolume(1);
      await _tts.setPitch(1);
      if (Platform.isAndroid) await _tts.setQueueMode(0);
      if (Platform.isIOS) await _tts.setSharedInstance(true);
      final selected = await _tts.setVoice({
        'name': _voice!['name']!,
        'locale': _voice!['locale']!,
        if (Platform.isIOS && _voice!['identifier'] != null)
          'identifier': _voice!['identifier']!,
      });
      if (selected != 1) {
        notice =
            'The offline Sinhala voice could not be selected. Check the device’s speech settings.';
        return;
      }
      available = true;
    } catch (_) {
      notice =
          'Text-to-speech is unavailable. Check your device’s speech settings.';
    } finally {
      isChecking = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    await stop();
    // Reinitialize the selected Android engine after voice data/settings change.
    if (Platform.isAndroid) {
      try {
        final engine = await _tts.getDefaultEngine;
        if (engine is String && engine.isNotEmpty) await _tts.setEngine(engine);
      } catch (_) {
        /* Configuration below reports a useful availability message. */
      }
    }
    _initialization = null;
    await initialize();
  }

  Future<void> play(String text) async {
    await initialize();
    if (_disposed || !available || text.trim().isEmpty) return;
    await stop();
    final generation = ++_generation;
    isSpeaking = true;
    notice = null;
    _notify();
    try {
      final max = Platform.isAndroid
          ? await _tts.getMaxSpeechInputLength
          : null;
      final limit = max is int && max >= 16 ? (max < 3000 ? max : 3000) : 3000;
      for (final chunk in speechChunks(text, maxCodeUnits: limit)) {
        if (_disposed || generation != _generation) break;
        final result = await _tts.speak(chunk, focus: true);
        if (generation == _generation && result != 1) {
          throw StateError('Speech did not complete');
        }
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        notice =
            'Could not read this text. Check your offline Sinhala voice and try again.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        isSpeaking = false;
        _notify();
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    isSpeaking = false;
    try {
      await _tts.stop();
    } catch (_) {
      /* An unavailable engine is handled on play. */
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
