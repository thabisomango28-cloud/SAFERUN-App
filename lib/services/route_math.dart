import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Shortest distance in metres from [p] to the route line [route].
/// Works on each segment (not just the points), so a straight stretch with
/// few points is still measured correctly.
double distanceToRouteM(LatLng p, List<LatLng> route) {
  if (route.isEmpty) return double.infinity;
  if (route.length == 1) {
    return const Distance().as(LengthUnit.Meter, p, route.first);
  }

  // Flat-earth approximation: accurate enough over a few kilometres.
  const metresPerDegLat = 111320.0;
  final metresPerDegLng = metresPerDegLat * cos(p.latitudeInRad);

  var best = double.infinity;
  for (var i = 0; i < route.length - 1; i++) {
    // Segment A->B with p at the origin (0, 0).
    final ax = (route[i].longitude - p.longitude) * metresPerDegLng;
    final ay = (route[i].latitude - p.latitude) * metresPerDegLat;
    final bx = (route[i + 1].longitude - p.longitude) * metresPerDegLng;
    final by = (route[i + 1].latitude - p.latitude) * metresPerDegLat;

    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0
        ? 0.0
        : ((-ax * dx + -ay * dy) / len2).clamp(0.0, 1.0).toDouble();

    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final d = sqrt(cx * cx + cy * cy);
    if (d < best) best = d;
  }
  return best;
}
