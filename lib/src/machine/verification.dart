import 'dart:async';

/// A pending "show me an admin" check guarding settings and profiles.
class AdminVerification {
  AdminVerification({required this.deadlineMs});

  final int deadlineMs;
  final _result = Completer<bool>();

  /// No admin showed up in time; the user may fall back to the passcode.
  bool denied = false;

  Future<bool> get result => _result.future;
  bool get done => _result.isCompleted;

  void complete(bool granted) {
    if (!_result.isCompleted) _result.complete(granted);
  }
}
