/// Spots a blink in a stream of eye-open probabilities: eyes clearly open,
/// then briefly closed, then open again. A printed or on-screen photo never
/// does that.
class BlinkDetector {
  static const _open = 0.7;
  static const _closed = 0.3;
  static const _reopened = 0.6;

  /// Longer than this with eyes shut is not a blink.
  static const _maxClosedMs = 900;

  bool _sawOpen = false;
  int? _closedAtMs;
  bool _blinked = false;

  bool get blinked => _blinked;

  /// [eyesOpen] is the probability both eyes are open, null when unknown.
  void add(double? eyesOpen, int nowMs) {
    if (eyesOpen == null || _blinked) return;
    final closedAt = _closedAtMs;
    if (closedAt == null) {
      if (eyesOpen >= _open) {
        _sawOpen = true;
      } else if (_sawOpen && eyesOpen <= _closed) {
        _closedAtMs = nowMs;
      }
    } else if (eyesOpen >= _reopened) {
      _blinked = nowMs - closedAt <= _maxClosedMs;
      _closedAtMs = null;
    } else if (nowMs - closedAt > _maxClosedMs) {
      _closedAtMs = null;
      _sawOpen = false;
    }
  }

  void reset() {
    _sawOpen = false;
    _closedAtMs = null;
    _blinked = false;
  }
}
