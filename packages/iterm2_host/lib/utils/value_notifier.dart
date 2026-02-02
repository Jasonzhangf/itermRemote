typedef VoidCallback = void Function();

/// Minimal ValueNotifier implementation for non-Flutter environments.
///
/// This keeps the host module testable on the Dart VM without depending
/// on Flutter's foundation library.
class ValueNotifier<T> {
  T _value;
  final List<VoidCallback> _listeners = <VoidCallback>[];

  ValueNotifier(this._value);

  T get value => _value;

  set value(T newValue) {
    if (identical(_value, newValue) || _value == newValue) {
      _value = newValue;
      return;
    }
    _value = newValue;
    _notifyListeners();
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    _listeners.clear();
  }

  void _notifyListeners() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }
}

