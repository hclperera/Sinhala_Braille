import 'package:flutter/material.dart';
import '../storage/scan_store.dart';
import 'sinhala_text.dart';

class SavedScansScreen extends StatefulWidget {
  const SavedScansScreen({super.key, required this.store});
  final ScanStore store;
  @override
  State<SavedScansScreen> createState() => _SavedScansScreenState();
}

class _SavedScansScreenState extends State<SavedScansScreen> {
  late Future<List<SavedScan>> _scans;
  @override
  void initState() {
    super.initState();
    _scans = widget.store.list();
  }

  String _date(DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date.toLocal());

  Future<void> _delete(SavedScan scan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved scan?'),
        content: const Text(
          'This removes its saved photo and text from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.delete(scan.id);
      if (mounted) setState(() => _scans = widget.store.list());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete this scan. Please retry.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved scans')),
    body: FutureBuilder<List<SavedScan>>(
      future: _scans,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load saved scans.'),
                TextButton(
                  onPressed: () => setState(() => _scans = widget.store.list()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final scans = snapshot.data!;
        if (scans.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No saved scans yet. Use Save scan after reading a page.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: scans.length,
          itemBuilder: (context, index) {
            final scan = scans[index];
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: SinhalaText(scan.text, maxLines: 2, fontSize: 18),
                subtitle: Text(_date(scan.savedAt)),
                onTap: () => Navigator.pop(context, scan),
                trailing: IconButton(
                  tooltip: 'Delete saved scan',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(scan),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
