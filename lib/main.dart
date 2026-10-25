import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'models.dart';
import 'recorder.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only: the manifest locks the activity, this keeps the engine in
  // step when the platform ignores the attribute (multi-window, large screens).
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  runApp(const BgVoiceApp());
}

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
  // The mic keeps a fixed layout slot so feedback appearing below it can never
  // move it; only the circle inside the slot animates while recording.
  static const double _micSlotSize = 168;
  static const double _micIdleSize = 156;
  // Slot centre as a share of the free height: a bit above the middle, leaving
  // room for the result card underneath.
  static const double _micCenterFraction = 0.42;

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
    _client.close();
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
            ListTile(title: Text(gateway.name), subtitle: Text(gateway.url)),
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
      final result = await _client.sendCommand(gateway: gateway, wavPath: path);
      if (!mounted) return;
      setState(() {
        _result = result;
        _status = null;
      });
      if (result.speak && result.audioUrl != null) {
        unawaited(_playReply(gateway, result.audioUrl!));
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

  Future<void> _playReply(Gateway gateway, String relative) async {
    try {
      final reply = await _client.fetchAudio(
        gateway: gateway,
        relative: relative,
      );
      await _player.play(BytesSource(reply.bytes, mimeType: reply.mimeType));
    } catch (_) {
      // Playback is best effort: the text reply is already on screen. A stale
      // audio_url (gateway restarted) or a wrong secret must not look like a
      // failed command.
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final topGap = math.max(
                    8.0,
                    constraints.maxHeight * _micCenterFraction -
                        _micSlotSize / 2,
                  );
                  return Column(
                    children: [
                      SizedBox(height: topGap),
                      _buildMicButton(theme),
                      const SizedBox(height: 18),
                      Text(
                        _recording ? 'Пусни за изпращане' : 'Задръж и говори',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      // Feedback and the result card live in their own fixed
                      // region, so showing or hiding them never re-centres the
                      // mic and breaks a hold gesture.
                      Expanded(child: _buildFeedback(theme)),
                    ],
                  );
                },
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

  Widget _buildFeedback(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_status != null) Text(_status!, textAlign: TextAlign.center),
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
    );
  }

  Widget _buildMicButton(ThemeData theme) {
    final color = _recording
        ? theme.colorScheme.error
        : _sending
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    return SizedBox(
      width: _micSlotSize,
      height: _micSlotSize,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _onPressStart(),
          onTapUp: (_) => _onPressEnd(),
          onTapCancel: _onPressCancel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _recording ? _micSlotSize : _micIdleSize,
            height: _recording ? _micSlotSize : _micIdleSize,
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
  late final TextEditingController _secretController;
  bool _obscureSecret = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _urlController = TextEditingController(text: widget.existing?.url ?? '');
    _secretController = TextEditingController(
      text: widget.existing?.secret ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _secretController.dispose();
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
    final secret = _secretController.text.trim();
    final gateway = widget.existing == null
        ? Gateway(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            url: url,
            secret: secret,
          )
        : widget.existing!.copyWith(name: name, url: url, secret: secret);
    Navigator.of(context).pop(gateway);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Редактирай gateway' : 'Нов gateway'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'http://192.168.1.10:8125',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Име (по избор)',
                hintText: 'Вкъщи',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secretController,
              obscureText: _obscureSecret,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Тайна (X-API-Key)',
                helperText: 'По избор; от BGV_API_KEY на gateway',
                suffixIcon: IconButton(
                  tooltip: _obscureSecret ? 'Покажи тайната' : 'Скрий тайната',
                  icon: Icon(
                    _obscureSecret
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureSecret = !_obscureSecret),
                ),
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
