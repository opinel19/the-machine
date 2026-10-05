import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../storage/identity_store.dart';

/// Where the Machine is watching from: GPS position and the district it is
/// in, for the HUD, captures and the numbers' history.
class LocationService extends ChangeNotifier {
  /// Places are looked up again after moving this far, or this long.
  static const _replaceMeters = 200.0;
  static const _replaceInterval = Duration(minutes: 1);

  StreamSubscription<Position>? _positions;
  Geocoding? _geocoding;
  Position? _lastPlaced;
  DateTime? _lastPlacedAt;
  bool _starting = false;

  Position? position;

  /// District and city, upper-cased the Machine's way ("KADIKOY, ISTANBUL").
  String? place;

  /// The user said no, or location services are off.
  bool unavailable = false;

  bool get running => _positions != null;

  Future<void> start() async {
    if (running || _starting) return;
    _starting = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        unavailable = true;
        notifyListeners();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        unavailable = true;
        notifyListeners();
        return;
      }
      unavailable = false;
      _positions = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen(_onPosition, onError: (Object e) => debugPrint('Location stream failed: $e'));
    } on Object catch (e) {
      debugPrint('Location unavailable: $e');
      unavailable = true;
      notifyListeners();
    } finally {
      _starting = false;
    }
  }

  void stop() {
    _positions?.cancel();
    _positions = null;
    position = null;
    notifyListeners();
  }

  void _onPosition(Position p) {
    position = p;
    notifyListeners();
    final last = _lastPlaced, at = _lastPlacedAt;
    final moved = last == null || Geolocator.distanceBetween(last.latitude, last.longitude, p.latitude, p.longitude) > _replaceMeters;
    final stale = at == null || DateTime.now().difference(at) > _replaceInterval;
    if (moved || stale) unawaited(_lookUpPlace(p));
  }

  Future<void> _lookUpPlace(Position p) async {
    _lastPlaced = p;
    _lastPlacedAt = DateTime.now();
    try {
      final marks = await (_geocoding ??= Geocoding()).placemarkFromCoordinates(p.latitude, p.longitude);
      if (marks.isEmpty) return;
      final m = marks.first;
      final district = [m.subLocality, m.subAdministrativeArea, m.locality].firstWhere(
        (s) => s != null && s.isNotEmpty,
        orElse: () => null,
      );
      final city = [m.administrativeArea, m.locality, m.country].firstWhere(
        (s) => s != null && s.isNotEmpty && s != district,
        orElse: () => null,
      );
      final name = [?district, ?city].join(', ');
      if (name.isEmpty) return;
      place = IdentityStore.normalizeName(name);
      notifyListeners();
    } on Object catch (e) {
      debugPrint('Reverse geocoding failed: $e');
    }
  }

  @override
  void dispose() {
    _positions?.cancel();
    super.dispose();
  }
}

/// "41.00823°N 28.97836°E": how the Machine's feeds print positions.
String formatCoordinates(double latitude, double longitude, {int digits = 5}) =>
    '${latitude.abs().toStringAsFixed(digits)}°${latitude >= 0 ? 'N' : 'S'} '
    '${longitude.abs().toStringAsFixed(digits)}°${longitude >= 0 ? 'E' : 'W'}';
