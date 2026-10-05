import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../machine/designation.dart';
import '../vision/face_embedder.dart';

/// Someone the Machine knows: one of its admins, or a person the user gave a
/// designation (relevant, threat, asset, ...).
class Identity {
  Identity({
    required this.id,
    required this.designation,
    required List<Float32List> embeddings,
    List<Float32List> learned = const [],
    this.name,
    this.thumbnail,
    this.createdMs = 0,
    this.thresholdOffset = 0,
  }) : embeddings = List.unmodifiable(embeddings),
       learned = List.unmodifiable(learned),
       centroid = meanDirection([...embeddings, ...learned]);

  factory Identity.fromJson(Map<String, dynamic> json) {
    List<Float32List> decode(Object? list) => [
      for (final encoded in (list as List?) ?? const [])
        Float32List.view(Uint8List.fromList(base64Decode(encoded as String)).buffer),
    ];
    return Identity(
      id: json['id'] as String,
      designation: Designation.values.byName(json['designation'] as String),
      name: json['name'] as String?,
      embeddings: decode(json['embeddings']),
      learned: decode(json['learned']),
      thumbnail: json['thumbnail'] as String?,
      createdMs: (json['created'] as int?) ?? 0,
      thresholdOffset: (json['thresholdOffset'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final Designation designation;

  /// Display name; every admin has one, others may.
  final String? name;

  /// Samples from enrolment (admins) or from when the person was flagged.
  final List<Float32List> embeddings;

  /// Samples picked up later while recognising the face (admins only).
  final List<Float32List> learned;

  /// Face image file name inside the store's thumbnail directory.
  final String? thumbnail;
  final int createdMs;

  /// Added to the global match threshold for this person: negative for a
  /// face that is hard to recognise, positive for one that gets confused.
  final double thresholdOffset;

  /// Mean direction of all samples; faces are compared against this.
  final Float32List centroid;

  String get displayName => name ?? id;

  Iterable<Float32List> get samples => embeddings.followedBy(learned);

  Identity copyWith({
    Designation? designation,
    String? name,
    List<Float32List>? embeddings,
    List<Float32List>? learned,
    String? thumbnail,
    double? thresholdOffset,
  }) => Identity(
    id: id,
    designation: designation ?? this.designation,
    name: name ?? this.name,
    embeddings: embeddings ?? this.embeddings,
    learned: learned ?? this.learned,
    thumbnail: thumbnail ?? this.thumbnail,
    createdMs: createdMs,
    thresholdOffset: thresholdOffset ?? this.thresholdOffset,
  );

  Map<String, Object> toJson() {
    List<String> encode(List<Float32List> list) => [
      for (final e in list) base64Encode(e.buffer.asUint8List(e.offsetInBytes, e.lengthInBytes)),
    ];
    return {
      'id': id,
      'designation': designation.name,
      'name': ?name,
      'embeddings': encode(embeddings),
      if (learned.isNotEmpty) 'learned': encode(learned),
      'thumbnail': ?thumbnail,
      'created': createdMs,
      if (thresholdOffset != 0) 'thresholdOffset': thresholdOffset,
    };
  }
}

class IdentityMatch {
  const IdentityMatch(this.identity, this.similarity);

  final Identity identity;
  final double similarity;
}

/// Face identities, persisted as JSON with face thumbnails next to it.
class IdentityStore extends ChangeNotifier {
  IdentityStore({Future<Directory> Function()? directory}) : _directory = directory ?? _defaultDirectory;

  /// Most learned samples an identity keeps; the oldest go first.
  static const maxLearned = 25;

  /// Where identities lived before they moved into a file.
  static const _legacyPrefsKey = 'poi.identities.v1';

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/machine');

  final Future<Directory> Function() _directory;
  final List<Identity> _identities = [];
  final _random = math.Random();
  Directory? _dir;
  Timer? _pendingSave;

  List<Identity> get all => List.unmodifiable(_identities);

  List<Identity> get admins => [
    for (final identity in _identities)
      if (identity.designation == Designation.admin) identity,
  ];

  /// Everyone who is not an admin, newest first.
  List<Identity> get flagged => [
    for (final identity in _identities.reversed)
      if (identity.designation != Designation.admin) identity,
  ];

  int count(Designation designation) => _identities.where((i) => i.designation == designation).length;

  File? thumbnailFile(Identity identity) {
    final dir = _dir, name = identity.thumbnail;
    return dir == null || name == null ? null : File('${dir.path}/thumbs/$name');
  }

  /// Upper-cases a name and spells the letters the interface font lacks
  /// (Ğ, Ş, İ) the way an old terminal would.
  static String normalizeName(String name) => name
      .trim()
      .toUpperCase()
      .replaceAll('Ğ', 'G')
      .replaceAll('Ş', 'S')
      .replaceAll('İ', 'I')
      .replaceAll(RegExp(r'\s+'), ' ');

  /// First free default name: ADMIN 01, ADMIN 02, ...
  String suggestAdminName() {
    final taken = {for (final admin in admins) admin.name};
    for (var n = 1; ; n++) {
      final candidate = 'ADMIN ${n.toString().padLeft(2, '0')}';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  Future<void> load() async {
    final dir = _dir = await _directory();
    await Directory('${dir.path}/thumbs').create(recursive: true);
    final file = _file(dir);
    String? raw;
    var migrated = false;
    if (await file.exists()) {
      raw = await file.readAsString();
    } else {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_legacyPrefsKey);
      migrated = raw != null;
    }
    if (raw != null) {
      try {
        _identities
          ..clear()
          ..addAll([for (final json in jsonDecode(raw) as List) Identity.fromJson(json as Map<String, dynamic>)]);
      } on Object catch (e) {
        debugPrint('Ignoring unreadable identity store: $e');
      }
    }
    // Admins enrolled before profiles had names.
    for (var i = 0; i < _identities.length; i++) {
      final identity = _identities[i];
      if (identity.designation == Designation.admin && identity.name == null) {
        _identities[i] = identity.copyWith(name: suggestAdminName());
      }
    }
    if (migrated) {
      await _write();
      await (await SharedPreferences.getInstance()).remove(_legacyPrefsKey);
    }
    notifyListeners();
  }

  /// The known identity whose centroid is closest to [embedding], among those
  /// passing [where], skipping [excluding].
  IdentityMatch? bestMatch(Float32List embedding, {bool Function(Identity)? where, Identity? excluding}) {
    IdentityMatch? best;
    for (final identity in _identities) {
      if (identical(identity, excluding) || (where != null && !where(identity))) continue;
      final similarity = cosine(embedding, identity.centroid);
      if (best == null || similarity > best.similarity) best = IdentityMatch(identity, similarity);
    }
    return best;
  }

  Future<Identity> add(
    Designation designation,
    List<Float32List> embeddings, {
    String? name,
    Uint8List? thumbnailPng,
  }) async {
    final id = _newId(designation == Designation.admin ? 'A' : 'S');
    final identity = Identity(
      id: id,
      designation: designation,
      name: name == null ? null : normalizeName(name),
      embeddings: embeddings,
      thumbnail: thumbnailPng == null ? null : await _writeThumbnail(id, thumbnailPng),
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    _identities.add(identity);
    await _save();
    return identity;
  }

  /// Identities are immutable: stores an updated copy of [identity] in its
  /// place and returns it. New [embeddings] replace the learned ones too.
  Future<Identity> update(
    Identity identity, {
    Designation? designation,
    String? name,
    List<Float32List>? embeddings,
    Uint8List? thumbnailPng,
    double? thresholdOffset,
    bool keepLearned = false,
  }) async {
    String? thumbnail;
    if (thumbnailPng != null) {
      _deleteThumbnail(identity);
      thumbnail = await _writeThumbnail(identity.id, thumbnailPng);
    }
    final updated = identity.copyWith(
      designation: designation,
      name: name == null ? null : normalizeName(name),
      embeddings: embeddings,
      learned: embeddings == null || keepLearned ? null : const [],
      thumbnail: thumbnail,
      thresholdOffset: thresholdOffset,
    );
    final index = _identities.indexOf(identity);
    if (index < 0) {
      _identities.add(updated);
    } else {
      _identities[index] = updated;
    }
    await _save();
    return updated;
  }

  /// Adds a sample seen while recognising [identity]. Saved lazily, since
  /// this happens during recognition.
  Identity learn(Identity identity, Float32List embedding) {
    final index = _identities.indexOf(identity);
    if (index < 0) return identity;
    final learned = [...identity.learned, embedding];
    if (learned.length > maxLearned) learned.removeRange(0, learned.length - maxLearned);
    final updated = identity.copyWith(learned: learned);
    _identities[index] = updated;
    notifyListeners();
    _pendingSave?.cancel();
    _pendingSave = Timer(const Duration(seconds: 3), _write);
    return updated;
  }

  Future<void> remove(Identity identity) async {
    _identities.remove(identity);
    _deleteThumbnail(identity);
    await _save();
  }

  Future<void> removeAll(Designation designation) async {
    for (final identity in _identities.where((i) => i.designation == designation).toList()) {
      _identities.remove(identity);
      _deleteThumbnail(identity);
    }
    await _save();
  }

  /// Removes identities with [designation] that look like [centroid].
  Future<void> removeLookalikes(Designation designation, Float32List centroid, double threshold) async {
    final doomed = [
      for (final i in _identities)
        if (i.designation == designation && cosine(i.centroid, centroid) >= threshold) i,
    ];
    if (doomed.isEmpty) return;
    for (final identity in doomed) {
      _identities.remove(identity);
      _deleteThumbnail(identity);
    }
    await _save();
  }

  String _newId(String prefix) {
    while (true) {
      final id = '$prefix-${_random.nextInt(0x10000).toRadixString(16).toUpperCase().padLeft(4, '0')}';
      if (!_identities.any((i) => i.id == id)) return id;
    }
  }

  static File _file(Directory dir) => File('${dir.path}/identities.json');

  Future<String?> _writeThumbnail(String id, Uint8List png) async {
    final dir = _dir;
    if (dir == null) return null;
    // A fresh name per write, so image caches never show a stale face.
    final name = '$id-${DateTime.now().millisecondsSinceEpoch}.png';
    await File('${dir.path}/thumbs/$name').writeAsBytes(png);
    return name;
  }

  void _deleteThumbnail(Identity identity) {
    final file = thumbnailFile(identity);
    if (file != null) file.delete().catchError((Object _) => file);
  }

  Future<void> _save() async {
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    _pendingSave?.cancel();
    _pendingSave = null;
    final dir = _dir;
    if (dir == null) return;
    final file = _file(dir);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final i in _identities) i.toJson()]));
    await tmp.rename(file.path);
  }

  @override
  void dispose() {
    if (_pendingSave != null) _write();
    super.dispose();
  }
}
