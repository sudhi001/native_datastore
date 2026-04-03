import 'package:flutter/material.dart';
import 'package:native_datastore/native_datastore.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native DataStore Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const DataStoreDemo(),
    );
  }
}

class DataStoreDemo extends StatefulWidget {
  const DataStoreDemo({super.key});

  @override
  State<DataStoreDemo> createState() => _DataStoreDemoState();
}

class _DataStoreDemoState extends State<DataStoreDemo> {
  final _datastore = NativeDatastore();
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();
  String _output = 'No data yet';

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _setString() async {
    final key = _keyController.text.trim();
    final value = _valueController.text.trim();
    if (key.isEmpty || value.isEmpty) return;
    await _datastore.setString(key, value);
    _showMessage('Saved "$key" = "$value"');
    await _loadAll();
  }

  Future<void> _getString() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    final value = await _datastore.getString(key);
    _showMessage('$key = ${value ?? "(not found)"}');
  }

  Future<void> _remove() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    final removed = await _datastore.remove(key);
    _showMessage(removed ? 'Removed "$key"' : '"$key" not found');
    await _loadAll();
  }

  Future<void> _clearAll() async {
    await _datastore.clear();
    _showMessage('Cleared all data');
    await _loadAll();
  }

  Future<void> _loadAll() async {
    final all = await _datastore.getAll();
    setState(() {
      if (all.isEmpty) {
        _output = 'DataStore is empty';
      } else {
        _output = all.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      }
    });
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Native DataStore Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: 'Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _valueController,
              decoration: const InputDecoration(
                labelText: 'Value',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _setString,
                  child: const Text('Set String'),
                ),
                OutlinedButton(
                  onPressed: _getString,
                  child: const Text('Get String'),
                ),
                OutlinedButton(
                  onPressed: _loadAll,
                  child: const Text('Get All'),
                ),
                FilledButton.tonal(
                  onPressed: _remove,
                  child: const Text('Remove'),
                ),
                FilledButton.tonal(
                  onPressed: _clearAll,
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Stored Data:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(_output, style: const TextStyle(fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
