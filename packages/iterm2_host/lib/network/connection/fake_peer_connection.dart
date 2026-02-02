/// Simulated WebRTC peer connection for local testing.
///
/// This class mimics the state transitions and failure modes of a real
/// WebRTC connection without requiring actual network/WebRTC dependencies.
///
/// States: New -> Checking -> Connected | Failed
enum PeerConnectionState { new_, checking, connected, failed, disconnected }

enum PeerConnectionError { timeout, iceFailed, signalingFailed, none }

class FakePeerConnectionConfig {
  final Duration timeToConnect;
  final Duration timeToFail;
  final double failureProbability;
  final bool simulateLatency;

  const FakePeerConnectionConfig({
    this.timeToConnect = const Duration(milliseconds: 800),
    this.timeToFail = const Duration(seconds: 3),
    this.failureProbability = 0.0,
    this.simulateLatency = true,
  });
}

class FakePeerConnection {
  final FakePeerConnectionConfig _config;
  PeerConnectionState _state = PeerConnectionState.new_;
  PeerConnectionError _error = PeerConnectionError.none;
  final List<void Function(PeerConnectionState)> _stateListeners = [];
  final List<void Function(PeerConnectionError)> _errorListeners = [];

  FakePeerConnection({FakePeerConnectionConfig? config})
      : _config = config ?? const FakePeerConnectionConfig();

  PeerConnectionState get state => _state;
  PeerConnectionError get error => _error;
  bool get isConnected => _state == PeerConnectionState.connected;
  bool get isFailed => _state == PeerConnectionState.failed;

  void onStateChange(void Function(PeerConnectionState) callback) {
    _stateListeners.add(callback);
  }

  void onError(void Function(PeerConnectionError) callback) {
    _errorListeners.add(callback);
  }

  /// Start connection simulation.
  Future<void> connect({required String ipv6, required int port}) async {
    if (_state != PeerConnectionState.new_) {
      throw StateError('PeerConnection already started');
    }

    _setState(PeerConnectionState.checking);

    if (_config.simulateLatency) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // Deterministic-enough pseudo randomness for simulation.
    final rng = DateTime.now().microsecond;
    final shouldFail = _config.failureProbability > 0 &&
        (rng % 100) < (_config.failureProbability * 100);

    if (shouldFail) {
      await Future<void>.delayed(_config.timeToFail);
      _setError(PeerConnectionError.iceFailed);
      _setState(PeerConnectionState.failed);
      return;
    }

    await Future<void>.delayed(_config.timeToConnect);
    _setState(PeerConnectionState.connected);
  }

  void disconnect() {
    if (_state == PeerConnectionState.connected ||
        _state == PeerConnectionState.checking) {
      _setState(PeerConnectionState.disconnected);
    }
  }

  void reset() {
    _state = PeerConnectionState.new_;
    _error = PeerConnectionError.none;
  }

  void _setState(PeerConnectionState newState) {
    _state = newState;
    for (final listener in _stateListeners) {
      listener(newState);
    }
  }

  void _setError(PeerConnectionError err) {
    _error = err;
    for (final listener in _errorListeners) {
      listener(err);
    }
  }
}

