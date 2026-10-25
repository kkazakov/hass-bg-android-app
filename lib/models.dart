class Gateway {
  Gateway({
    required this.id,
    required this.name,
    required this.url,
    this.secret = '',
  });

  final String id;
  final String name;
  final String url;

  /// Optional shared key sent as `X-API-Key`, matching the gateway's
  /// `BGV_API_KEY`. Empty means the gateway has authentication disabled.
  final String secret;

  bool get hasSecret => secret.trim().isNotEmpty;

  factory Gateway.fromJson(Map<String, dynamic> json) => Gateway(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    secret: (json['secret'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    if (hasSecret) 'secret': secret.trim(),
  };

  Gateway copyWith({String? name, String? url, String? secret}) => Gateway(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    secret: secret ?? this.secret,
  );

  /// Accepts `host:port`, `http://host:port`, `https://host/path/`.
  /// Adds `http://` when no scheme is given and strips trailing slashes.
  static String normalizeUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (!value.contains('://')) value = 'http://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String defaultName(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'Gateway';
    return uri.host;
  }
}

class CommandResult {
  CommandResult({
    required this.kind,
    required this.speak,
    required this.text,
    required this.transcript,
    required this.audioUrl,
    required this.intent,
    required this.matchScore,
    required this.totalMs,
  });

  final String kind;
  final bool speak;
  final String text;
  final String transcript;
  final String? audioUrl;
  final String? intent;
  final double? matchScore;
  final double? totalMs;

  bool get noMatch => kind == 'no_match';

  factory CommandResult.fromJson(Map<String, dynamic> json) {
    final matched = json['matched'];
    final timings = json['timings'];
    return CommandResult(
      kind: (json['kind'] as String?) ?? 'action',
      speak: (json['speak'] as bool?) ?? false,
      text: (json['text'] as String?) ?? '',
      transcript: (json['transcript'] as String?) ?? '',
      audioUrl: json['audio_url'] as String?,
      intent: matched is Map ? matched['intent'] as String? : null,
      matchScore: matched is Map
          ? (matched['score'] as num?)?.toDouble()
          : null,
      totalMs: timings is Map
          ? (timings['total_ms'] as num?)?.toDouble()
          : null,
    );
  }
}
