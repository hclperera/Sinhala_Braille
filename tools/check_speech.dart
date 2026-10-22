import 'dart:io';
import 'package:sinhala_braille/speech/speech_policy.dart';

void main() {
  final voice = offlineSinhalaVoice([
    {
      'name': 'network',
      'locale': 'si-LK',
      'network_required': '1',
      'quality': 'very high',
    },
    {
      'name': 'missing',
      'locale': 'si-LK',
      'network_required': '0',
      'features': 'notInstalled',
    },
    {'name': 'unknown', 'locale': 'si-LK'},
    {'name': 'English', 'locale': 'en-US', 'network_required': '0'},
    {
      'name': 'Sinhala offline',
      'locale': 'si-LK',
      'network_required': '0',
      'features': '',
    },
  ], android: true);
  if (voice?['name'] != 'Sinhala offline') {
    throw StateError('Offline Sinhala selection failed');
  }
  if (offlineSinhalaVoice([
        {'name': 'network', 'locale': 'si-LK', 'network_required': true},
      ], android: true) !=
      null) {
    throw StateError('Network voice accepted');
  }
  if (offlineSinhalaVoice([
        {'name': 'Sinhala', 'locale': 'si-LK', 'identifier': 'installed'},
      ], android: false) ==
      null) {
    throw StateError('iOS voice selection failed');
  }
  for (final text in [
    'සිංහල පාඨය කියවන්න. ' * 600,
    'ක්‍රි' * 100,
    '😀' * 100,
  ]) {
    final chunks = speechChunks(text, maxCodeUnits: 80);
    if (chunks.any((s) => s.length > 80)) {
      throw StateError('Speech chunk too long');
    }
    String normalized(String s) => s.replaceAll(RegExp(r'\s+'), '');
    if (normalized(chunks.join()) != normalized(text)) {
      throw StateError('Speech text was lost');
    }
  }
  stdout.writeln(
    'PASS: offline voice filtering, missing voice rejection, iOS selection and long-page chunking.',
  );
}
