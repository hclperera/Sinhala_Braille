import 'package:characters/characters.dart';

/// A network voice is never silently substituted for an offline voice.
Map<String, String>? offlineSinhalaVoice(
  List<dynamic> voices, {
  required bool android,
}) {
  final candidates = <Map<String, String>>[];
  for (final raw in voices) {
    if (raw is! Map) continue;
    final voice = raw.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
    final locale = (voice['locale'] ?? '').replaceAll('_', '-').toLowerCase();
    if (locale != 'si' && !locale.startsWith('si-')) continue;
    if ((voice['name'] ?? '').isEmpty) continue;
    if (android) {
      final network = raw['network_required'];
      if (network != false &&
          network != 0 &&
          network != '0' &&
          network != 'false') {
        continue;
      }
      if ((voice['features'] ?? '').contains('notInstalled')) continue;
    }
    candidates.add(voice);
  }
  candidates.sort((a, b) {
    int quality(Map<String, String> v) => switch (v['quality']) {
      'premium' || 'very high' => 4,
      'enhanced' || 'high' => 3,
      'normal' => 2,
      _ => 1,
    };
    final rank = quality(b).compareTo(quality(a));
    return rank != 0 ? rank : (a['name'] ?? '').compareTo(b['name'] ?? '');
  });
  return candidates.isEmpty ? null : candidates.first;
}

/// Split long pages below the platform input limit without breaking graphemes.
List<String> speechChunks(String text, {int maxCodeUnits = 3000}) {
  if (maxCodeUnits < 16) {
    throw ArgumentError.value(maxCodeUnits, 'maxCodeUnits');
  }
  final chunks = <String>[];
  var buffer = StringBuffer(), length = 0;
  for (final word in RegExp(r'\S+\s*').allMatches(text)) {
    final value = word.group(0)!;
    if (length + value.length <= maxCodeUnits) {
      buffer.write(value);
      length += value.length;
      continue;
    }
    if (length > 0) {
      chunks.add(buffer.toString().trim());
      buffer = StringBuffer();
      length = 0;
    }
    for (final character in value.characters) {
      if (character.length > maxCodeUnits) {
        throw const FormatException(
          'A text segment exceeds the speech input limit',
        );
      }
      if (length + character.length > maxCodeUnits) {
        chunks.add(buffer.toString().trim());
        buffer = StringBuffer();
        length = 0;
      }
      buffer.write(character);
      length += character.length;
    }
  }
  if (length > 0) chunks.add(buffer.toString().trim());
  return chunks.where((s) => s.isNotEmpty).toList();
}
