import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A number the Machine gave out.
class NumberRecord {
  NumberRecord({
    required this.ssn,
    required this.issuedAt,
    required this.subjectCode,
    this.signature,
    this.facePng,
    DateTime? lastSeenAt,
    this.sightings = 0,
    this.latitude,
    this.longitude,
    this.place,
    this.lastLatitude,
    this.lastLongitude,
  }) : lastSeenAt = lastSeenAt ?? issuedAt;

  factory NumberRecord.fromJson(Map<String, dynamic> json) {
    final signature = json['signature'] as String?;
    final face = json['face'] as String?;
    return NumberRecord(
      ssn: json['ssn'] as String,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(json['issued'] as int),
      subjectCode: json['code'] as String,
      signature: signature == null ? null : Float32List.view(Uint8List.fromList(base64Decode(signature)).buffer),
      facePng: face == null ? null : base64Decode(face),
      lastSeenAt: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int),
      sightings: json['sightings'] as int? ?? 0,
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lon'] as num?)?.toDouble(),
      place: json['place'] as String?,
      lastLatitude: (json['lastLat'] as num?)?.toDouble(),
      lastLongitude: (json['lastLon'] as num?)?.toDouble(),
    );
  }

  final String ssn;
  final DateTime issuedAt;
  final String subjectCode;

  /// Face embedding of the person, to spot them again; null if their face was
  /// never seen clearly.
  Float32List? signature;
  Uint8List? facePng;
  DateTime lastSeenAt;

  /// Times the person showed up again after their number was given out.
  int sightings;

  /// Where the number was given out, and where the person was last seen.
  final double? latitude;
  final double? longitude;
  final String? place;
  double? lastLatitude;
  double? lastLongitude;

  Map<String, Object> toJson() {
    final signature = this.signature, face = facePng;
    return {
      'ssn': ssn,
      'issued': issuedAt.millisecondsSinceEpoch,
      'code': subjectCode,
      if (signature != null) 'signature': base64Encode(signature.buffer.asUint8List(signature.offsetInBytes, signature.lengthInBytes)),
      if (face != null) 'face': base64Encode(face),
      'lastSeen': lastSeenAt.millisecondsSinceEpoch,
      'sightings': sightings,
      'lat': ?latitude,
      'lon': ?longitude,
      'place': ?place,
      'lastLat': ?lastLatitude,
      'lastLon': ?lastLongitude,
    };
  }
}

/// Every number given out, newest first, persisted on the device.
class NumberLog extends ChangeNotifier {
  NumberLog({Future<Directory> Function()? directory}) : _directory = directory ?? _defaultDirectory;

  static const capacity = 50;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/machine');

  final Future<Directory> Function() _directory;
  final List<NumberRecord> _records = [];
  File? _file;

  List<NumberRecord> get records => List.unmodifiable(_records);

  Future<void> load() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = _file = File('${dir.path}/numbers.json');
    if (!await file.exists()) return;
    try {
      _records
        ..clear()
        ..addAll([for (final j in jsonDecode(await file.readAsString()) as List) NumberRecord.fromJson(j as Map<String, dynamic>)]);
    } on Object catch (e) {
      debugPrint('Ignoring unreadable number log: $e');
    }
    notifyListeners();
  }

  Future<void> add(NumberRecord record) async {
    _records.insert(0, record);
    if (_records.length > capacity) _records.removeRange(capacity, _records.length);
    await save();
  }

  Future<void> remove(NumberRecord record) async {
    _records.remove(record);
    await save();
  }

  Future<void> clear() async {
    _records.clear();
    await save();
  }

  Future<void> save() async {
    notifyListeners();
    final file = _file;
    if (file == null) return;
    await file.writeAsString(jsonEncode([for (final r in _records) r.toJson()]));
  }
}
