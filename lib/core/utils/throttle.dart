import 'dart:async';

/// Rate limiter with a trailing edge.
///
/// Continuous controls (a servo slider, a joystick) produce values far faster
/// than a BLE link should carry them. This lets the leading value through
/// immediately, drops the flood in between, and guarantees the *final* value is
/// still delivered — dropping the last one would leave the vehicle acting on a
/// stale position.
class Throttle<T> {
  Throttle({required this.interval, required this.onEmit});

  final Duration interval;
  final void Function(T value) onEmit;

  Timer? _timer;
  DateTime? _lastEmit;
  T? _pending;
  bool _hasPending = false;

  /// Offers a value. Emits now if the interval has elapsed, otherwise schedules
  /// it as the trailing value.
  void submit(T value) {
    final now = DateTime.now();
    final last = _lastEmit;

    if (last == null || now.difference(last) >= interval) {
      _emit(value, now);
      return;
    }

    _pending = value;
    _hasPending = true;
    _timer ??= Timer(interval - now.difference(last), _flushPending);
  }

  /// Emits [value] immediately, cancelling anything queued.
  ///
  /// Used for commands that must never wait behind a throttle — above all,
  /// STOP.
  void emitNow(T value) {
    cancel();
    _emit(value, DateTime.now());
  }

  void _flushPending() {
    _timer = null;
    if (!_hasPending) return;
    final value = _pending as T;
    _hasPending = false;
    _pending = null;
    _emit(value, DateTime.now());
  }

  void _emit(T value, DateTime at) {
    _lastEmit = at;
    onEmit(value);
  }

  /// Drops any queued value without emitting it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _hasPending = false;
  }

  void dispose() => cancel();
}

/// Delays an action until input has been quiet for [duration].
///
/// Used where only the settled value matters — committing a settings slider,
/// for instance — rather than every intermediate position.
class Debouncer {
  Debouncer({required this.duration});

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
