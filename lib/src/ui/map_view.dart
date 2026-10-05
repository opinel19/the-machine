import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../machine/machine_controller.dart';
import '../platform/location_service.dart';
import '../storage/number_log.dart';
import '../theme.dart';
import 'box_painter.dart';
import 'hud.dart';

/// OpenStreetMap tiles in grey, inverted for the Machine's dark feeds.
const _machineTiles = ColorFilter.matrix([
  -0.19, -0.64, -0.065, 0, 230, //
  -0.19, -0.64, -0.065, 0, 230,
  -0.19, -0.64, -0.065, 0, 230,
  0, 0, 0, 1, 0,
]);
const _samaritanTiles = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 8, //
  0.2126, 0.7152, 0.0722, 0, 8,
  0.2126, 0.7152, 0.0722, 0, 8,
  0, 0, 0, 1, 0,
]);

/// Where the Machine is watching from, and where its numbers were given out
/// and last seen. Dark map for the Machine, pale grey for Samaritan.
Future<void> showSurveillanceMap(BuildContext context, MachineController controller) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, _, _) => _MapPage(controller: controller),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
}

class _MapPage extends StatelessWidget {
  const _MapPage({required this.controller});

  final MachineController controller;

  @override
  Widget build(BuildContext context) {
    final theme = controller.settings.theme;
    final samaritan = theme.isSamaritan;
    final position = controller.location.position;
    final here = position == null ? null : LatLng(position.latitude, position.longitude);
    final records = [
      for (final r in controller.numbers.records)
        if (r.latitude != null && r.longitude != null) r,
    ];
    final center = here ??
        (records.isEmpty ? const LatLng(40.7580, -73.9855) : LatLng(records.first.latitude!, records.first.longitude!));
    final ink = samaritan ? SamaritanColors.ink : MachineColors.text;
    final paper = samaritan ? SamaritanColors.paper : Colors.black;
    return Material(
      color: paper,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: here == null && records.isEmpty ? 11 : 15,
              backgroundColor: paper,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.emirozkunduz.personOfInterest',
                tileBuilder: (context, tile, _) =>
                    ColorFiltered(colorFilter: samaritan ? _samaritanTiles : _machineTiles, child: tile),
              ),
              PolylineLayer(
                polylines: [
                  for (final r in records)
                    if (r.lastLatitude != null && r.lastLongitude != null && r.sightings > 0)
                      Polyline(
                        points: [LatLng(r.latitude!, r.longitude!), LatLng(r.lastLatitude!, r.lastLongitude!)],
                        color: theme.accent.withValues(alpha: 0.8),
                        strokeWidth: 2,
                        pattern: StrokePattern.dashed(segments: const [8, 6]),
                      ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final r in records) ..._numberMarkers(r, theme),
                  if (here != null)
                    Marker(
                      point: here,
                      width: 120,
                      height: 70,
                      child: _Pin(label: controller.feed.label.split(' // ').first, theme: theme, own: true),
                    ),
                ],
              ),
            ],
          ),
          // Keeps the header readable over street names.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: MediaQuery.paddingOf(context).top + 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [paper, paper.withValues(alpha: 0.85), paper.withValues(alpha: 0)],
                    stops: const [0, 0.6, 1],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (samaritan) ...[const Padding(padding: EdgeInsets.only(top: 4), child: SamaritanTriangle()), const SizedBox(width: 10)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          samaritan ? 'SAMARITAN // GLOBAL VIEW' : 'SURVEILLANCE MAP',
                          style: theme.style(size: 14, color: theme.accent, spacing: theme.spacing * 2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          here == null
                              ? 'LOCATION UNAVAILABLE'
                              : '${formatCoordinates(here.latitude, here.longitude)}\n${controller.location.place ?? ''}',
                          style: theme.style(size: 10, color: ink, spacing: 1),
                        ),
                        Text(
                          '${records.length.toString().padLeft(2, '0')} NUMBERS ON THE MAP',
                          style: theme.style(size: 10, color: ink.withValues(alpha: 0.6), spacing: 1),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, color: ink)),
                ],
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: MediaQuery.paddingOf(context).bottom + 4,
            child: Text(
              '© OPENSTREETMAP CONTRIBUTORS',
              style: theme.style(size: 8, color: ink.withValues(alpha: 0.6), spacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _numberMarkers(NumberRecord r, ModeTheme theme) => [
    Marker(
      point: LatLng(r.latitude!, r.longitude!),
      width: 130,
      height: 70,
      child: _Pin(label: r.ssn, theme: theme),
    ),
    if (r.sightings > 0 && r.lastLatitude != null && r.lastLongitude != null)
      Marker(
        point: LatLng(r.lastLatitude!, r.lastLongitude!),
        width: 130,
        height: 70,
        child: _Pin(label: 'LAST SEEN', theme: theme, faint: true),
      ),
  ];
}

/// A small Machine box (or Samaritan circle) with a label under it.
class _Pin extends StatelessWidget {
  const _Pin({required this.label, required this.theme, this.own = false, this.faint = false});

  final String label;
  final ModeTheme theme;
  final bool own;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final color = own ? theme.accent : (theme.isSamaritan ? SamaritanColors.ink : Colors.white);
    return Opacity(
      opacity: faint ? 0.6 : 1,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CustomPaint(painter: _PinPainter(color, samaritan: theme.isSamaritan)),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: theme.isSamaritan ? Colors.white.withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.7),
            child: Text(label, style: theme.style(size: 9, color: color, spacing: 1)),
          ),
        ],
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.color, {required this.samaritan});

  final Color color;
  final bool samaritan;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    if (samaritan) {
      canvas
        ..drawCircle(rect.center, rect.width / 2, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color)
        ..drawCircle(rect.center, 2, Paint()..color = SamaritanColors.red);
      return;
    }
    paintMachineBox(canvas, rect, BoxColors.all(color));
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color || old.samaritan != samaritan;
}
