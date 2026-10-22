// Port of Infox_Backend/services/translation.py; upstream revision is recorded
// in tools/reference/revisions.json. Bit order is dots 1,2,3,4,5,6.
class TranslationResult {
  const TranslationResult(this.text, this.warnings);
  final String text;
  final List<String> warnings;
}

const independentVowels = <String, String>{
  '100000': 'අ',
  '001110': 'ආ',
  '111011': 'ඇ',
  '110111': 'ඈ',
  '010100': 'ඉ',
  '001010': 'ඊ',
  '101001': 'උ',
  '110011': 'ඌ',
  '100010': 'එ',
  '010001': 'ඒ',
  '001100': 'ඓ',
  '101101': 'ඔ',
  '101010': 'ඕ',
  '010101': 'ඖ',
};
const vowelSigns = <String, String>{
  '001110': 'ා',
  '111011': 'ැ',
  '110111': 'ෑ',
  '010100': 'ි',
  '001010': 'ී',
  '101001': 'ු',
  '110011': 'ූ',
  '100010': 'ෙ',
  '010001': 'ේ',
  '001100': 'ෛ',
  '101101': 'ො',
  '101010': 'ෝ',
  '010101': 'ෞ',
};
const consonants = <String, String>{
  '101000': 'ක',
  '000101': 'ඛ',
  '110110': 'ග',
  '110001': 'ඝ',
  '001101': 'ඞ',
  '100100': 'ච',
  '100001': 'ඡ',
  '010110': 'ජ',
  '001011': 'ඣ',
  '010010': 'ඤ',
  '011111': 'ට',
  '010111': 'ඨ',
  '110101': 'ඩ',
  '111111': 'ඪ',
  '101011': 'ණ',
  '011110': 'ත',
  '100111': 'ථ',
  '100110': 'ද',
  '011101': 'ධ',
  '101110': 'න',
  '111100': 'ප',
  '100011': 'ඵ',
  '110000': 'බ',
  '000110': 'භ',
  '101100': 'ම',
  '101111': 'ය',
  '111010': 'ර',
  '111000': 'ල',
  '111001': 'ව',
  '100101': 'ෂ',
  '111101': 'ශ',
  '011100': 'ස',
  '110010': 'හ',
  '000111': 'ළ',
  '110100': 'ෆ',
  '111110': 'ඥ',
};
const digits = <String, String>{
  '100000': '1',
  '110000': '2',
  '100100': '3',
  '100110': '4',
  '100010': '5',
  '110100': '6',
  '110110': '7',
  '110010': '8',
  '010100': '9',
  '010110': '0',
};
const punctuation = <String, String>{
  '010000': ',',
  '011000': ';',
  '010010': ':',
  '010011': '.',
  '011010': '!',
  '011001': '?',
  '011011': '()',
  '001011': '"',
  '001001': '-',
};
const _sanyaka = {'ග': 'ඟ', 'ජ': 'ඦ', 'ඩ': 'ඬ', 'ද': 'ඳ', 'බ': 'ඹ'};

TranslationResult translateBraille(List<String> input) {
  final codes = input.map((code) {
    if (code.runes.length == 1 &&
        code.runes.first >= 0x2800 &&
        code.runes.first <= 0x283f) {
      final bits = code.runes.first - 0x2800;
      return List.generate(6, (i) => bits & (1 << i) == 0 ? '0' : '1').join();
    }
    return code;
  }).toList();
  final output = <String>[];
  final warnings = <String>[];
  var number = false, consonant = false, paren = false, quote = false;
  void warn(int i, String reason) => warnings.add('Cell ${i + 1}: $reason');
  void emit(String char, {bool dead = false}) {
    if (output.isNotEmpty &&
        output.last.endsWith('්') &&
        (char == 'ර' || char == 'ය')) {
      output.add('\u200d');
    }
    output.add('$char${dead ? '්' : ''}');
  }

  for (var i = 0; i < codes.length;) {
    final code = codes[i];
    final next = i + 1 < codes.length ? codes[i + 1] : null;
    if (code == '000000' || code == '\n') {
      output.add(code == '\n' ? '\n' : ' ');
      number = consonant = false;
      i++;
      continue;
    }
    if (!RegExp(r'^[01]{6}$').hasMatch(code)) {
      output.add('�');
      warn(i, 'Invalid or uncertain cell');
      number = consonant = false;
      i++;
      continue;
    }
    // Explicit English letter sign is supported only for Roman list labels.
    if (code == '000011') {
      var previous = i - 1;
      while (previous >= 0 && codes[previous] == '000000') {
        previous--;
      }
      const roman = {
        '010100': 'i',
        '111001': 'v',
        '101101': 'x',
        '111000': 'l',
        '100100': 'c',
        '100110': 'd',
        '101100': 'm',
      };
      var end = i + 1;
      var label = '';
      while (end < codes.length &&
          roman.containsKey(codes[end]) &&
          label.length < 15) {
        label += roman[codes[end]]!;
        end++;
      }
      if ((previous < 0 || codes[previous] == '\n') &&
          label.isNotEmpty &&
          RegExp(
            r'^m{0,3}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})$',
          ).hasMatch(label) &&
          end < codes.length &&
          codes[end] == '010011' &&
          (end + 1 == codes.length ||
              codes[end + 1] == '000000' ||
              codes[end + 1] == '\n')) {
        output.add('$label.');
        warn(i, 'Roman list label interpreted using the English letter sign');
        number = consonant = false;
        i = end + 1;
        continue;
      }
    }
    if (code == '001111') {
      number = digits.containsKey(next);
      consonant = false;
      if (!number) {
        output.add('�');
        warn(i, 'Number sign has no following digit');
      }
      i++;
      continue;
    }
    if (number && digits.containsKey(code)) {
      output.add(digits[code]!);
      i++;
      continue;
    }
    number = false;
    if (code == '001000' && next == '001000') {
      output.add('ඃ');
      consonant = false;
      i += 2;
      continue;
    }
    if ((code == '000010' || code == '000001') &&
        (next == '111010' || next == '111000')) {
      if (next == '111010') {
        output.add(
          consonant
              ? (code == '000010' ? 'ෘ' : 'ෲ')
              : (code == '000010' ? 'ඍ' : 'ඎ'),
        );
      } else if (consonant) {
        output.add(code == '000010' ? 'ෟ' : '�');
        if (code != '000010') warn(i, 'Long vocalic l sign needs review');
      } else {
        output.add(code == '000010' ? 'ඏ' : 'ඐ');
      }
      consonant = false;
      i += 2;
      continue;
    }
    if (code == '000100') {
      var j = i + 1;
      final nasal = j < codes.length && codes[j] == '011000';
      if (nasal) j++;
      final char = j < codes.length ? consonants[codes[j]] : null;
      if (char != null && (!nasal || _sanyaka.containsKey(char))) {
        emit(nasal ? _sanyaka[char]! : char, dead: true);
        i = j + 1;
      } else {
        output.add('�');
        warn(i, 'Unresolved virama prefix');
        i++;
      }
      consonant = false;
      continue;
    }
    if (code == '011000') {
      final char = consonants[next];
      if (_sanyaka.containsKey(char)) {
        warn(i, 'Ambiguous prefix interpreted as sanyaka');
        emit(_sanyaka[char]!);
        consonant = true;
        i += 2;
      } else {
        output.add(';');
        consonant = false;
        i++;
      }
      continue;
    }
    if (consonant && vowelSigns.containsKey(code)) {
      output.add(vowelSigns[code]!);
      consonant = false;
    } else if (code == '001000') {
      output.add('ං');
      consonant = false;
    } else if (code == '011011') {
      output.add(paren ? ')' : '(');
      paren = !paren;
      consonant = false;
    } else if (code == '001011' && quote) {
      output.add('”');
      quote = false;
      consonant = false;
      warn(i, 'Ambiguous cell interpreted as closing quote');
    } else if (code == '011001' &&
        (i == 0 || codes[i - 1] == '000000' || codes[i - 1] == '\n') &&
        codes.skip(i + 1).contains('001011')) {
      output.add('“');
      quote = true;
      consonant = false;
      warn(i, 'Ambiguous cell interpreted as opening quote');
    } else if (consonants.containsKey(code)) {
      if (code == '010010' || code == '001011') {
        warn(i, 'Letter/punctuation ambiguity: kept letter');
      }
      emit(consonants[code]!);
      consonant = true;
    } else if (independentVowels.containsKey(code)) {
      output.add(independentVowels[code]!);
      consonant = false;
    } else if (punctuation.containsKey(code)) {
      output.add(punctuation[code]!);
      consonant = false;
    } else {
      output.add('�');
      warn(i, 'Unsupported cell');
      consonant = false;
    }
    i++;
  }
  if (paren || quote) warnings.add('Unclosed bracket or quote');
  // Canonical Sinhala split vowel sequences emitted by this decoder.
  final text = output
      .join()
      .replaceAll('ෝ', 'ෝ')
      .replaceAll('ො', 'ො')
      .replaceAll('ෞ', 'ෞ')
      .replaceAll('ේ', 'ේ');
  return TranslationResult(text, warnings);
}
