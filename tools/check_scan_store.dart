import 'dart:io';
import 'package:sinhala_braille/storage/scan_store.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('infox-scan-store-');
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  try {
    final source = File('${root.path}/photo');
    await source.writeAsBytes([1, 2, 3, 4]);
    final folder = Directory('${root.path}/saved');
    final store = ScanStore(folder);
    check((await store.list()).isEmpty, 'First run must have empty history');
    final scan = await store.save(
      text: 'ප්‍රේමය හා ආදරය',
      originalText: '� හා ආදරය',
      warnings: ['Cell 1: uncertain'],
      seconds: 12.5,
      dots: 123,
      slices: 6,
      imagePath: source.path,
    );
    await source.delete();
    final restored = (await ScanStore(folder).list()).single;
    check(
      restored.text == scan.text && restored.originalText == '� හා ආදරය',
      'Unicode, corrections and raw text must survive reopening',
    );
    check(
      restored.warnings.single == 'Cell 1: uncertain' &&
          restored.dots == 123 &&
          restored.seconds == 12.5 &&
          restored.slices == 6,
      'Recognition metadata must survive reopening',
    );
    check(
      (await File(restored.imagePath).readAsBytes()).join() == '1234',
      'Saved image must survive source deletion',
    );
    try {
      await store.save(
        text: 'test',
        originalText: 'test',
        warnings: [],
        seconds: 0,
        dots: 0,
        slices: 0,
        imagePath: source.path,
      );
      throw StateError('Missing source was accepted');
    } on FileSystemException {
      /* Expected: no partial scan published. */
    }
    check((await store.list()).length == 1, 'Failed save published an entry');
    check(
      (await folder.list().toList()).length == 1,
      'Failed save left staging files',
    );
    try {
      await store.delete('../photo');
      throw StateError('Invalid identifier was accepted');
    } on ArgumentError {
      /* Expected. */
    }
    await store.delete(scan.id);
    check((await store.list()).isEmpty, 'Delete must remove the saved scan');
    stdout.writeln(
      'Saved scan persistence, Unicode, image retention, rollback and deletion passed.',
    );
  } finally {
    await root.delete(recursive: true);
  }
}
