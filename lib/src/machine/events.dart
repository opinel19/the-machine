import 'package:flutter/foundation.dart';

enum EventKind { info, admin, alert, number, system }

class MachineEvent {
  MachineEvent(this.kind, this.text) : time = DateTime.now();

  final EventKind kind;
  final String text;
  final DateTime time;
}

/// What the Machine noticed, newest last.
class EventLog extends ChangeNotifier {
  static const capacity = 80;

  final List<MachineEvent> _events = [];

  List<MachineEvent> get events => List.unmodifiable(_events);

  void add(EventKind kind, String text) {
    _events.add(MachineEvent(kind, text));
    if (_events.length > capacity) _events.removeAt(0);
    notifyListeners();
  }
}
