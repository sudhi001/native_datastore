import 'dart:convert';
import 'dart:typed_data';

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
  String _selectedType = 'String';

  final _types = [
    'String',
    'Bool',
    'Int',
    'Double',
    'StringList',
    'Bytes',
    'DateTime',
    'Map',
  ];

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  String get _valueHint {
    switch (_selectedType) {
      case 'Bool':
        return 'true or false';
      case 'Int':
        return 'e.g. 42';
      case 'Double':
        return 'e.g. 3.14';
      case 'StringList':
        return 'comma-separated, e.g. a,b,c';
      case 'Bytes':
        return 'comma-separated bytes, e.g. 0,1,255';
      case 'DateTime':
        return 'ISO 8601, e.g. 2024-06-15T10:30:00Z';
      case 'Map':
        return 'JSON, e.g. {"name":"sudhi","age":30}';
      default:
        return 'Value';
    }
  }

  Future<void> _setValue() async {
    final key = _keyController.text.trim();
    final raw = _valueController.text.trim();
    if (key.isEmpty || raw.isEmpty) return;

    try {
      switch (_selectedType) {
        case 'String':
          await _datastore.setString(key, raw);
          _showMessage('Saved String "$key" = "$raw"');
        case 'Bool':
          final val = raw.toLowerCase() == 'true';
          await _datastore.setBool(key, val);
          _showMessage('Saved Bool "$key" = $val');
        case 'Int':
          final val = int.parse(raw);
          await _datastore.setInt(key, val);
          _showMessage('Saved Int "$key" = $val');
        case 'Double':
          final val = double.parse(raw);
          await _datastore.setDouble(key, val);
          _showMessage('Saved Double "$key" = $val');
        case 'StringList':
          final val = raw.split(',').map((s) => s.trim()).toList();
          await _datastore.setStringList(key, val);
          _showMessage('Saved StringList "$key" = $val');
        case 'Bytes':
          final val = Uint8List.fromList(
            raw.split(',').map((s) => int.parse(s.trim())).toList(),
          );
          await _datastore.setBytes(key, val);
          _showMessage('Saved Bytes "$key" (${val.length} bytes)');
        case 'DateTime':
          final val = DateTime.parse(raw);
          await _datastore.setDateTime(key, val);
          _showMessage('Saved DateTime "$key" = ${val.toIso8601String()}');
        case 'Map':
          final val = Map<String, dynamic>.from(
            jsonDecode(raw) as Map,
          );
          await _datastore.setMap(key, val);
          _showMessage('Saved Map "$key"');
      }
    } on FormatException {
      _showMessage('Invalid $_selectedType value: "$raw"');
      return;
    }
    await _loadAll();
  }

  Future<void> _getValue() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;

    Object? value;
    switch (_selectedType) {
      case 'String':
        value = await _datastore.getString(key);
      case 'Bool':
        value = await _datastore.getBool(key);
      case 'Int':
        value = await _datastore.getInt(key);
      case 'Double':
        value = await _datastore.getDouble(key);
      case 'StringList':
        value = await _datastore.getStringList(key);
      case 'Bytes':
        value = await _datastore.getBytes(key);
      case 'DateTime':
        final dt = await _datastore.getDateTime(key);
        value = dt?.toIso8601String();
      case 'Map':
        value = await _datastore.getMap(key);
    }
    _showMessage('$key ($_selectedType) = ${value ?? "(not found)"}');
  }

  Future<void> _remove() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    final removed = await _datastore.remove(key);
    _showMessage(removed ? 'Removed "$key"' : '"$key" not found');
    await _loadAll();
  }

  Future<void> _setSampleData() async {
    await _datastore.clear();
    await _datastore.setString('username', 'sudhi');
    await _datastore.setBool('darkMode', true);
    await _datastore.setInt('loginCount', 42);
    await _datastore.setDouble('rating', 4.8);
    await _datastore.setStringList('tags', ['flutter', 'dart', 'mobile']);
    await _datastore.setBytes('token', Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]));
    await _datastore.setDateTime('lastLogin', DateTime.now());
    await _datastore.setMap('profile', {'name': 'sudhi', 'level': 5, 'active': true});
    _showMessage('Saved sample data for all 8 types');
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
        _output = all.entries
            .map((e) => '${e.key} (${e.value.runtimeType}): ${e.value}')
            .join('\n');
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _valueController,
                    decoration: InputDecoration(
                      labelText: 'Value',
                      hintText: _valueHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedType,
                  items: _types
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _setValue,
                  child: Text('Set $_selectedType'),
                ),
                OutlinedButton(
                  onPressed: _getValue,
                  child: Text('Get $_selectedType'),
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
                FilledButton(
                  onPressed: _setSampleData,
                  child: const Text('Set All Types'),
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
