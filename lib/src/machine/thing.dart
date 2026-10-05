import 'dart:ui';

/// What the Machine marks besides people.
enum ThingKind {
  vehicle('VEHICLE'),
  watercraft('WATERCRAFT'),
  aircraft('AIRCRAFT');

  const ThingKind(this.label);

  final String label;

  /// Kind for an ImageNet label, or null for everything else. Some tempting
  /// labels are left out on purpose: "plane" is a carpenter's tool, "kite" a
  /// bird, "balloon" a party balloon.
  static ThingKind? ofLabel(String label) => _kinds[label.toLowerCase()];

  static const _kinds = {
    'ambulance': vehicle, 'amphibian': vehicle, 'beach wagon': vehicle, 'cab': vehicle,
    'convertible': vehicle, 'fire engine': vehicle, 'forklift': vehicle, 'garbage truck': vehicle,
    'go-kart': vehicle, 'golfcart': vehicle, 'half track': vehicle, 'jeep': vehicle,
    'limousine': vehicle, 'minibus': vehicle, 'minivan': vehicle, 'moped': vehicle,
    'motor scooter': vehicle, 'moving van': vehicle, 'passenger car': vehicle, 'pickup': vehicle,
    'police van': vehicle, 'racer': vehicle, 'recreational vehicle': vehicle, 'school bus': vehicle,
    'snowmobile': vehicle, 'sports car': vehicle, 'streetcar': vehicle, 'tank': vehicle,
    'tow truck': vehicle, 'tractor': vehicle, 'trailer truck': vehicle, 'trolleybus': vehicle,
    'electric locomotive': vehicle, 'steam locomotive': vehicle, 'bullet train': vehicle,
    'freight car': vehicle, 'mountain bike': vehicle, 'bicycle-built-for-two': vehicle,
    'car wheel': vehicle, 'grille': vehicle, 'car mirror': vehicle,
    'aircraft carrier': watercraft, 'canoe': watercraft, 'catamaran': watercraft,
    'container ship': watercraft, 'fireboat': watercraft, 'gondola': watercraft,
    'lifeboat': watercraft, 'liner': watercraft, 'paddlewheel': watercraft, 'pirate': watercraft,
    'schooner': watercraft, 'speedboat': watercraft, 'submarine': watercraft,
    'trimaran': watercraft, 'wreck': watercraft, 'yawl': watercraft,
    'airliner': aircraft, 'airship': aircraft, 'warplane': aircraft, 'space shuttle': aircraft,
  };
}

/// A vehicle, boat or aircraft the Machine is tracking.
class Thing {
  Thing({required this.id, required this.kind, required this.label, required this.code, required this.firstSeenMs})
    : lastSeenMs = firstSeenMs;

  final int id;
  ThingKind kind;

  /// What it is, e.g. SPORTS CAR.
  String label;

  /// Plate-like code for vehicles and boats, flight number for aircraft.
  final String code;
  final int firstSeenMs;
  int lastSeenMs;
  Rect box = Rect.zero;
}
