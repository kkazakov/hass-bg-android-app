import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class StoredGateways {
  StoredGateways(this.gateways, this.activeId);

  final List<Gateway> gateways;
  final String? activeId;
}

class GatewayStore {
  static const _gatewaysKey = 'gateways_v1';
  static const _activeKey = 'active_gateway_v1';

  Future<StoredGateways> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_gatewaysKey);
    final gateways = <Gateway>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              gateways.add(Gateway.fromJson(item));
            }
          }
        }
      } catch (_) {
        // Corrupt storage: start clean rather than crash the app.
      }
    }
    var activeId = prefs.getString(_activeKey);
    if (activeId != null && !gateways.any((g) => g.id == activeId)) {
      activeId = null;
    }
    if (activeId == null && gateways.isNotEmpty) {
      activeId = gateways.first.id;
    }
    return StoredGateways(gateways, activeId);
  }

  Future<void> save(List<Gateway> gateways, String? activeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _gatewaysKey,
      jsonEncode(gateways.map((g) => g.toJson()).toList()),
    );
    if (activeId == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, activeId);
    }
  }
}
