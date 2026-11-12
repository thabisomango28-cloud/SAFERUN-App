import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

enum TripType { oneWay, outAndBack, loop }

String tripTypeLabel(TripType t) => switch (t) {
  TripType.oneWay => 'One way',
  TripType.outAndBack => 'Out and back',
  TripType.loop => 'Loop',
};

class RouteOption {
  final String label;
  final List<LatLng> points;
  final double distanceM;
  final double durationS; // walking time from OpenRouteService

  const RouteOption({
    required this.label,
    required this.points,
    required this.distanceM,
    required this.durationS,
  });

  double get km => distanceM / 1000;
  int get walkMinutes => (durationS / 60).round();
}

class PlaceResult {
  final String name;
  final LatLng point;
  const PlaceResult({required this.name, required this.point});
}

class RoutingException implements Exception {
  final String message;
  RoutingException(this.message);
  @override
  String toString() => message;
}

/// Talks to OpenRouteService (free): place search and walking routes.
class RoutingService {
  static const _host = 'api.openrouteservice.org';

  Map<String, String> get _headers => {
    'Authorization': AppConfig.orsApiKey,
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json, application/geo+json',
  };

  // ---------- place search ----------

  Future<List<PlaceResult>> search(String text, LatLng? focus) async {
    final params = {
      'api_key': AppConfig.orsApiKey,
      'text': text,
      'boundary.country': 'ZA',
      'size': '5',
      if (focus != null) 'focus.point.lon': focus.longitude.toString(),
      if (focus != null) 'focus.point.lat': focus.latitude.toString(),
    };
    final res = await http
        .get(Uri.https(_host, '/geocode/search', params))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw RoutingException(_errorMessage(res));

    final features = (jsonDecode(res.body)['features'] as List?) ?? [];
    return features.map<PlaceResult>((f) {
      final c = f['geometry']['coordinates'] as List;
      return PlaceResult(
        name: (f['properties']['label'] ?? 'Unnamed place') as String,
        point: LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      );
    }).toList();
  }

  // ---------- routes ----------

  /// Up to 3 alternative walking routes from [from] to [to].
  Future<List<RouteOption>> oneWay(LatLng from, LatLng to) async {
    final coords = [
      [from.longitude, from.latitude],
      [to.longitude, to.latitude],
    ];
    try {
      return _parse(
        await _post({
          'coordinates': coords,
          'alternative_routes': {
            'target_count': 3,
            'share_factor': 0.6,
            'weight_factor': 1.6,
          },
        }),
        'Route',
      );
    } on RoutingException {
      // Alternatives are not always available (e.g. very long routes).
      return _parse(await _post({'coordinates': coords}), 'Route');
    }
  }

  /// Same road out and back: the route doubled, the second half reversed.
  Future<List<RouteOption>> outAndBack(LatLng from, LatLng to) async {
    final options = await oneWay(from, to);
    return options
        .map(
          (r) => RouteOption(
            label: r.label,
            points: [...r.points, ...r.points.reversed.skip(1)],
            distanceM: r.distanceM * 2,
            durationS: r.durationS * 2,
          ),
        )
        .toList();
  }

  /// Round-trip loops from [start]. ORS builds loops randomly, and the
  /// requested length is only a guide, so we ask for 3 seeds and let the
  /// user pick from the real distances.
  Future<List<RouteOption>> loops(LatLng start, int lengthM) async {
    final results = await Future.wait(
      [1, 2, 3].map((seed) async {
        try {
          final parsed = _parse(
            await _post({
              'coordinates': [
                [start.longitude, start.latitude],
              ],
              'options': {
                'round_trip': {'length': lengthM, 'points': 3, 'seed': seed},
              },
            }),
            'Loop ${String.fromCharCode(64 + seed)}',
          );
          return parsed.isEmpty ? null : parsed.first;
        } on RoutingException {
          return null;
        }
      }),
    );

    final ok = results.whereType<RouteOption>().toList();
    if (ok.isEmpty) {
      throw RoutingException(
        'Could not build a loop here. Try another distance, or start from a road.',
      );
    }
    return ok;
  }

  // ---------- helpers ----------

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.https(_host, '/v2/directions/foot-walking/geojson'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw RoutingException(_errorMessage(res));
  }

  List<RouteOption> _parse(Map<String, dynamic> json, String prefix) {
    final features = (json['features'] as List?) ?? [];
    final out = <RouteOption>[];
    for (var i = 0; i < features.length; i++) {
      final f = features[i] as Map<String, dynamic>;
      final coords = (f['geometry']['coordinates'] as List)
          .map<LatLng>(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList();
      final summary = f['properties']['summary'];
      out.add(
        RouteOption(
          label: features.length == 1 ? prefix : '$prefix ${i + 1}',
          points: coords,
          distanceM: (summary['distance'] as num).toDouble(),
          durationS: (summary['duration'] as num).toDouble(),
        ),
      );
    }
    return out;
  }

  String _errorMessage(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      return 'OpenRouteService rejected the key. Check app_config.dart.';
    }
    if (res.statusCode == 429) {
      return 'Too many requests. Wait a minute and try again.';
    }
    try {
      final err = jsonDecode(res.body)['error'];
      final msg = err is Map ? err['message'] : err;
      if (msg != null) return msg.toString();
    } catch (_) {}
    return 'Could not get a route (error ${res.statusCode}).';
  }
}
