import 'dart:async';

/// Utility class for debouncing save operations
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer(this.delay);

  void run(Function action) {
    _timer?.cancel();
    _timer = Timer(delay, () => action());
  }
}
