import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/routing_service.dart';
import 'session_setup_screen.dart';

/// Map screen: shows your location, lets you pick where you're going
/// (or a loop distance), and shows route options.
class PlanRouteScreen extends StatefulWidget {
  const PlanRouteScreen({super.key});

  @override
  State<PlanRouteScreen> createState() => _PlanRouteScreenState();
}

class _PlanRouteScreenState extends State<PlanRouteScreen> {
  final _map = MapController();
  final _routing = RoutingService();
  final _searchCtrl = TextEditingController();

  TripType _type = TripType.oneWay;
  LatLng? _start;
  LatLng? _dest;
  double _loopKm = 5;

  List<PlaceResult> _results = [];
  List<RouteOption> _options = [];
  int _selected = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- actions ----------

  Future<void> _locate() async {
    try {
      final p = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      final here = LatLng(p.latitude, p.longitude);
      setState(() => _start = here);
      try {
        _map.move(here, 15);
      } catch (_) {}
    } catch (_) {
      _fail('Could not find your location. Turn on GPS and come back.');
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _searchPlaces() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 3) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _results = [];
    });
    try {
      final r = await _routing.search(q, _start);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) _error = 'No places found. Try another name.';
      });
    } on RoutingException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('No connection. Check your internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _choose(PlaceResult r) {
    setState(() {
      _dest = r.point;
      _searchCtrl.text = r.name;
      _results = [];
    });
    _findRoutes();
  }

  void _onMapTap(LatLng point) {
    if (_type == TripType.loop) return;
    setState(() {
      _dest = point;
      _searchCtrl.text = 'Dropped pin';
      _results = [];
    });
    _findRoutes();
  }

  Future<void> _findRoutes() async {
    final start = _start;
    if (start == null) {
      _fail('Still finding your location...');
      return;
    }
    if (_type != TripType.loop && _dest == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _options = [];
      _selected = 0;
    });
    try {
      final found = switch (_type) {
        TripType.oneWay => await _routing.oneWay(start, _dest!),
        TripType.outAndBack => await _routing.outAndBack(start, _dest!),
        TripType.loop => await _routing.loops(start, (_loopKm * 1000).round()),
      };
      if (!mounted) return;
      setState(() => _options = found);
      _fitRoute();
    } on RoutingException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('No connection. Check your internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fitRoute() {
    if (_options.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _map.fitCamera(
          CameraFit.coordinates(
            coordinates: _options[_selected].points,
            padding: const EdgeInsets.all(48),
          ),
        );
      } catch (_) {}
    });
  }

  void _continue({required bool withRoute}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionSetupScreen(
          route: withRoute ? _options[_selected] : null,
          tripType: withRoute ? _type : null,
        ),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Where are you going?')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<TripType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TripType.oneWay, label: Text('One way')),
                ButtonSegment(
                  value: TripType.outAndBack,
                  label: Text('Out and back'),
                ),
                ButtonSegment(value: TripType.loop, label: Text('Loop')),
              ],
              selected: {_type},
              onSelectionChanged: (s) {
                setState(() {
                  _type = s.first;
                  _options = [];
                  _error = null;
                });
                if (_type != TripType.loop && _dest != null) _findRoutes();
              },
            ),
          ),
          if (_type == TripType.loop) _loopControls() else _searchControls(),
          Expanded(child: _mapView(scheme)),
          _bottomPanel(scheme),
        ],
      ),
    );
  }

  Widget _searchControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchPlaces(),
            decoration: InputDecoration(
              hintText: 'Search a place, or tap the map',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _searchPlaces,
              ),
            ),
          ),
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 170),
              child: Card(
                margin: const EdgeInsets.only(top: 4),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in _results)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          r.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _choose(r),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _loopControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Row(
        children: [
          Text('${_loopKm.round()} km'),
          Expanded(
            child: Slider(
              min: 2,
              max: 15,
              divisions: 13,
              value: _loopKm,
              label: '${_loopKm.round()} km',
              onChanged: (v) => setState(() => _loopKm = v),
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _findRoutes,
            child: const Text('Find loops'),
          ),
        ],
      ),
    );
  }

  Widget _mapView(ColorScheme scheme) {
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _start ?? const LatLng(-29.0, 24.0),
        initialZoom: _start == null ? 5 : 15,
        onTap: (_, point) => _onMapTap(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.demo1',
        ),
        PolylineLayer(
          polylines: [
            for (var i = 0; i < _options.length; i++)
              if (i != _selected)
                Polyline(
                  points: _options[i].points,
                  strokeWidth: 4,
                  color: Colors.grey.shade600,
                ),
            if (_options.isNotEmpty)
              Polyline(
                points: _options[_selected].points,
                strokeWidth: 6,
                color: scheme.secondary,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            if (_start != null)
              Marker(
                point: _start!,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            if (_dest != null && _type != TripType.loop)
              Marker(
                point: _dest!,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: Icon(
                  Icons.location_on,
                  color: scheme.secondary,
                  size: 40,
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Widget _bottomPanel(ColorScheme scheme) {
    final hasRoute = _options.isNotEmpty;
    final sel = hasRoute ? _options[_selected] : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            if (hasRoute) ...[
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            '${_options[i].label} · ${_options[i].km.toStringAsFixed(1)} km',
                          ),
                          selected: _selected == i,
                          onSelected: (_) {
                            setState(() => _selected = i);
                            _fitRoute();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${sel!.km.toStringAsFixed(1)} km · about ${sel.walkMinutes} min walking'
                '${_type == TripType.outAndBack ? ' · same road both ways' : ''}'
                '${_type == TripType.loop ? ' · loop length is approximate' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _continue(withRoute: false),
                    child: const Text('Skip route'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: hasRoute
                        ? () => _continue(withRoute: true)
                        : null,
                    child: const Text('Use this route'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
