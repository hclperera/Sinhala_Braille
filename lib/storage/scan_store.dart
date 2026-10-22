import 'dart:convert';
import 'dart:io';

class SavedScan {
  const SavedScan({
    required this.id,
    required this.savedAt,
    required this.text,
    required this.originalText,
    required this.warnings,
    required this.seconds,
    required this.dots,
    required this.slices,
    required this.imagePath,
  });
  final String id, text, originalText, imagePath;
  final DateTime savedAt;
  final List<String> warnings;
  final double seconds;
  final int dots, slices;
}

/// Each scan is self-contained; a failed save never publishes a partial entry.
class ScanStore {
  ScanStore(this.directory);
  final Directory directory;
  static final _validId = RegExp(r'^\d+$');

  Future<SavedScan> save({
    required String text,
    required String originalText,
    required List<String> warnings,
    required double seconds,
    required int dots,
    required int slices,
    required String imagePath,
  }) async {
    await directory.create(recursive: true);
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final staging = Directory('${directory.path}/.$id');
    await staging.create();
    try {
      await File(imagePath).copy('${staging.path}/image');
      await File('${staging.path}/scan.json').writeAsString(
        jsonEncode({
          'version': 1,
          'id': id,
          'savedAt': now.toIso8601String(),
          'text': text,
          'originalText': originalText,
          'warnings': warnings,
          'seconds': seconds,
          'dots': dots,
          'slices': slices,
        }),
        flush: true,
      );
      final published = await staging.rename('${directory.path}/$id');
      return _read(published);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<SavedScan> _read(Directory folder) async {
    final data =
        jsonDecode(await File('${folder.path}/scan.json').readAsString())
            as Map<String, dynamic>;
    final id = folder.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (data['version'] != 1 || data['id'] != id) {
      throw const FormatException('Unsupported saved scan');
    }
    return SavedScan(
      id: id,
      savedAt: DateTime.parse(data['savedAt'] as String),
      text: data['text'] as String,
      originalText: data['originalText'] as String,
      warnings: (data['warnings'] as List).cast<String>(),
      seconds: (data['seconds'] as num).toDouble(),
      dots: data['dots'] as int,
      slices: data['slices'] as int,
      imagePath: '${folder.path}/image',
    );
  }

  Future<List<SavedScan>> list() async {
    if (!await directory.exists()) return [];
    final scans = <SavedScan>[];
    await for (final entity in directory.list(followLinks: false)) {
      final id = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entity is! Directory || !_validId.hasMatch(id)) continue;
      // Surface damaged entries rather than silently losing saved history.
      scans.add(await _read(entity));
    }
    scans.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return scans;
  }

  Future<void> delete(String id) async {
    if (!_validId.hasMatch(id)) throw ArgumentError.value(id, 'id');
    final folder = Directory('${directory.path}/$id');
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}
