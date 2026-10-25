import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'models.dart';
import 'recorder.dart';
import 'store.dart';

void main() => runApp(const BgVoiceApp());

class BgVoiceApp extends StatelessWidget {
  const BgVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0E7C66);
    return MaterialApp(
      title: 'BG Voice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GatewayStore _store = GatewayStore();
  final GatewayClient _client = GatewayClient();
  final VoiceRecorder _recorder = VoiceRecorder();
  final AudioPlayer _player = AudioPlayer();

  List<Gateway> _gateways = const [];
  String? _activeId;
  bool _loading = true;
  bool _recording = false;
  bool _sending = false;
  String? _status;
  String? _error;
  CommandResult? _result;
  bool _pressActive = false;
  bool _cancelled = false;
  DateTime? _pressedAt;

  Gateway? get _active {
    for (final gateway in _gateways) {
      if (gateway.id == _activeId) return gateway;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final stored = await _store.load();
    if (!mounted) return;
    setState(() {
      _gateways = stored.gateways;
      _activeId = stored.activeId;
      _loading = false;
    });
  }

  Future<void> _persist() => _store.save(_gateways, _activeId);

  void _select(Gateway gateway) {
    setState(() {
      _activeId = gateway.id;
      _result = null;
      _error = null;
      _status = null;
    });
    _persist();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addGateway() async {
    final gateway = await showDialog<Gateway>(
      context: context,
      builder: (_) => const GatewayDialog(),
    );
    if (gateway == null || !mounted) return;
    setState(() {
      _gateways = [..._gateways, gateway];
      _activeId = gateway.id;
    });
    await _persist();
  }

  Future<void> _editGateway(Gateway gateway) async {
    final updated = await showDialog<Gateway>(
      context: context,
      builder: (_) => GatewayDialog(existing: gateway),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _gateways = [
        for (final item in _gateways) item.id == updated.id ? updated : item,
      ];
    });
    await _persist();
  }

  Future<void> _deleteGateway(Gateway gateway) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изтриване'),
        content: Text('Да изтрия ли „${gateway.name}“?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отказ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Изтрий'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _gateways = _gateways.where((item) => item.id != gateway.id).toList();
      if (_activeId == gateway.id) {
        _activeId = _gateways.isEmpty ? null : _gateways.first.id;
      }
      _result = null;
      _error = null;
    });
    await _persist();
  }

  Future<void> _gatewayActions(Gateway gateway) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(gateway.name),
              subtitle: Text(gateway.url),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Редактирай'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Изтрий'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _editGateway(gateway);
    if (action == 'delete') await _deleteGateway(gateway);
  }

  bool _tooShort() {
    final started = _pressedAt;
    if (started == null) return false;
    return DateTime.now().difference(started).inMilliseconds < 450;
  }

  Future<void> _onPressStart() async {
    if (_pressActive || _sending || _recording) return;
    _pressActive = true;
    _cancelled = false;
    _pressedAt = DateTime.now();

    final gateway = _active;
    if (gateway == null) {
      _pressActive = false;
      _snack('Първо добави gateway (＋ горе вдясно)');
      return;
    }
    if (!await _recorder.ensurePermission()) {
      _pressActive = false;
      _snack('Няма разрешение за микрофон');
      return;
    }
    if (!_pressActive) return; // released while the permission dialog was open
    try {
      await _recorder.start();
    } catch (error) {
      _pressActive = false;
      _snack('Не мога да започна запис: $error');
      return;
    }
    if (!mounted) {
      await _recorder.stop();
      return;
    }
    if (!_pressActive) {
      // Released before the recorder actually started.
      final path = await _recorder.stop();
      if (path != null) {
        if (_cancelled || _tooShort()) {
          await _deleteFile(path);
          if (mounted) {
            setState(() => _status = _cancelled ? null : 'Задръж по-дълго');
          }
        } else {
          await _send(path);
        }
      }
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _status = 'Слушам…';
      _error = null;
      _result = null;
    });
  }

  Future<void> _onPressEnd() async {
    _pressActive = false;
    if (!_recording) return;
    final path = await _recorder.stop();
    if (!mounted) {
      if (path != null) await _deleteFile(path);
      return;
    }
    setState(() => _recording = false);
    if (path == null) return;
    if (_tooShort()) {
      await _deleteFile(path);
      if (!mounted) return;
      setState(() => _status = 'Задръж по-дълго');
      return;
    }
    await _send(path);
  }

  Future<void> _onPressCancel() async {
    _pressActive = false;
    _cancelled = true;
    if (!_recording) return;
    final path = await _recorder.stop();
    if (!mounted) {
      if (path != null) await _deleteFile(path);
      return;
    }
    setState(() {
      _recording = false;
      _status = null;
    });
    if (path != null) await _deleteFile(path);
  }

  Future<void> _send(String path) async {
    final gateway = _active;
    if (gateway == null) return;
    setState(() {
      _sending = true;
      _status = 'Изпращам…';
      _error = null;
    });
    try {
      final result = await _client.sendCommand(
        gateway: gateway,
        wavPath: path,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _status = null;
      });
      if (result.speak && result.audioUrl != null) {
        final uri = _client.audioUri(gateway, result.audioUrl!);
        unawaited(_player.play(UrlSource(uri.toString())).catchError((_) {}));
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _status = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Грешка: $error';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      await _deleteFile(path);
    }
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Temp file cleanup is best effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('BG Voice'),
        actions: [
          IconButton(
            tooltip: 'Добави gateway',
            icon: const Icon(Icons.add_link),
            onPressed: _addGateway,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            _buildGatewayStrip(theme),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildMicButton(theme),
                        const SizedBox(height: 18),
                        Text(
                          _recording ? 'Пусни за изпращане' : 'Задръж и говори',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (_status != null) Text(_status!),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        if (_result != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: _ResultCard(result: _result!),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _active == null
                    ? 'Няма избран gateway'
                    : '${_active!.name} · ${_active!.url}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGatewayStrip(ThemeData theme) {
    if (_loading) return const SizedBox(height: 8);
    if (_gateways.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          'Няма добавен gateway. Добави URL горе вдясно.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _gateways.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final gateway = _gateways[index];
          return GestureDetector(
            onLongPress: () => _gatewayActions(gateway),
            child: ChoiceChip(
              label: Text(gateway.name),
              selected: gateway.id == _activeId,
              onSelected: (_) => _select(gateway),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMicButton(ThemeData theme) {
    final color = _recording
        ? theme.colorScheme.error
        : _sending
            ? theme.colorScheme.secondary
            : theme.colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _onPressStart(),
      onTapUp: (_) => _onPressEnd(),
      onTapCancel: _onPressCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _recording ? 168 : 156,
        height: _recording ? 168 : 156,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: _recording ? 32 : 18,
              spreadRadius: _recording ? 8 : 2,
            ),
          ],
        ),
        child: _sending
            ? const Padding(
                padding: EdgeInsets.all(56),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            : Icon(
                _recording ? Icons.graphic_eq : Icons.mic,
                size: 72,
                color: theme.colorScheme.onPrimary,
              ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final CommandResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = result.noMatch
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final onTone = result.noMatch
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.transcript.isNotEmpty)
            Text(
              'Чух: ${result.transcript}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: onTone.withValues(alpha: 0.7),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            result.text,
            style: theme.textTheme.titleMedium?.copyWith(color: onTone),
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (result.kind.isNotEmpty) result.kind,
              if (result.intent != null && result.intent!.isNotEmpty)
                result.intent!,
              if (result.matchScore != null)
                '${result.matchScore!.toStringAsFixed(0)}%',
              if (result.totalMs != null)
                '${result.totalMs!.toStringAsFixed(0)} ms',
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: onTone.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class GatewayDialog extends StatefulWidget {
  const GatewayDialog({super.key, this.existing});

  final Gateway? existing;

  @override
  State<GatewayDialog> createState() => _GatewayDialogState();
}

class _GatewayDialogState extends State<GatewayDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _urlController = TextEditingController(text: widget.existing?.url ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = Gateway.normalizeUrl(_urlController.text);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      setState(() => _error = 'Невалиден URL (http://host:port)');
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? Gateway.defaultName(url)
        : _nameController.text.trim();
    final gateway = widget.existing == null
        ? Gateway(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            url: url,
          )
        : widget.existing!.copyWith(name: name, url: url);
    Navigator.of(context).pop(gateway);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Редактирай gateway' : 'Нов gateway'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'http://192.168.1.10:8080',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Име (по избор)',
              hintText: 'Вкъщи',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отказ'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Запази' : 'Добави'),
        ),
      ],
    );
  }
}
