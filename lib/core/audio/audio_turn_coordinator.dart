import 'dart:async';

/// Logical owners that may use the shared speech and playback resources.
///
/// These values describe product responsibilities. Native Android/iOS route
/// implementations stay behind their existing adapters.
enum AudioTurnOwner {
  mainAssistant,
  continuousTranslation,
  listeningLesson,
  vocabulary,
  backgroundLearning,
  legacy,
}

/// The exclusive activity performed by an [AudioTurnOwner].
enum AudioTurnMode {
  promptPlayback,
  mediaPlayback,
  speechCapture,
  recordedCapture,
  routePreparation,
}

enum AudioTurnDiagnosticType {
  acquireRequested,
  acquired,
  transferred,
  released,
  staleRelease,
  cancelled,
  timedOut,
  coordinatorDisposed,
}

class AudioTurnToken {
  const AudioTurnToken({
    required this.id,
    required this.generation,
    required this.owner,
    required this.mode,
  });

  final int id;
  final int generation;
  final AudioTurnOwner owner;
  final AudioTurnMode mode;

  @override
  bool operator ==(Object other) =>
      other is AudioTurnToken &&
      other.id == id &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(id, generation);

  @override
  String toString() =>
      'AudioTurnToken(id: $id, generation: $generation, '
      'owner: ${owner.name}, mode: ${mode.name})';
}

class AudioTurnDiagnostic {
  const AudioTurnDiagnostic({
    required this.type,
    required this.owner,
    required this.mode,
    required this.requestId,
    this.token,
    this.message,
  });

  final AudioTurnDiagnosticType type;
  final AudioTurnOwner owner;
  final AudioTurnMode mode;
  final int requestId;
  final AudioTurnToken? token;
  final String? message;
}

class AudioTurnAcquireCancelled implements Exception {
  const AudioTurnAcquireCancelled([this.reason = 'Audio turn was cancelled.']);

  final String reason;

  @override
  String toString() => reason;
}

class AudioTurnAcquireTimeout implements Exception {
  const AudioTurnAcquireTimeout(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'Audio turn acquisition timed out after $timeout.';
}

class AudioTurnCoordinatorDisposed implements Exception {
  const AudioTurnCoordinatorDisposed();

  @override
  String toString() => 'Audio turn coordinator has been disposed.';
}

/// Cancellation signal for a queued audio turn acquisition.
///
/// Cancellation never releases a lease that has already been granted. The
/// owner must release that lease explicitly, which prevents an old cancellation
/// callback from closing a newer turn.
class AudioTurnCancellation {
  bool _isCancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void _addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void _removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

class AudioTurnLease {
  AudioTurnLease._(this._coordinator, this.token);

  final AudioTurnCoordinator _coordinator;
  final AudioTurnToken token;
  bool _releaseRequested = false;

  AudioTurnOwner get owner => token.owner;
  AudioTurnMode get mode => token.mode;
  bool get isCurrent => _coordinator.isCurrent(token);

  /// Releases only this exact generation. Releasing an invalidated lease is a
  /// safe no-op and cannot close the current owner's newer turn.
  Future<void> release() {
    if (_releaseRequested) {
      return Future<void>.value();
    }
    _releaseRequested = true;
    return _coordinator._release(token);
  }

  /// Atomically hands the shared resource to another owner without exposing a
  /// gap where a queued request could interleave.
  Future<AudioTurnLease?> transfer({
    required AudioTurnOwner owner,
    required AudioTurnMode mode,
  }) async {
    final next = await _coordinator._transfer(
      from: token,
      owner: owner,
      mode: mode,
    );
    return next;
  }
}

/// Serializes access to shared microphone, playback and native audio routes.
///
/// Phase 1 introduces this coordinator without changing current feature timing.
/// Later phases use [CompatibilityAudioTurnAdapter] around the existing native
/// implementations before feature controllers are extracted.
class AudioTurnCoordinator {
  final List<_PendingAudioTurn> _pending = <_PendingAudioTurn>[];
  final StreamController<AudioTurnDiagnostic> _diagnostics =
      StreamController<AudioTurnDiagnostic>.broadcast(sync: true);
  AudioTurnLease? _current;
  int _nextRequestId = 0;
  int _generation = 0;
  bool _isDisposed = false;

  Stream<AudioTurnDiagnostic> get diagnostics => _diagnostics.stream;
  AudioTurnToken? get currentToken => _current?.token;
  bool get hasActiveTurn => _current != null;
  int get pendingCount => _pending.length;

  bool isCurrent(AudioTurnToken token) => _current?.token == token;

  Future<AudioTurnLease> acquire({
    required AudioTurnOwner owner,
    required AudioTurnMode mode,
    Duration? timeout,
    AudioTurnCancellation? cancellation,
  }) {
    if (_isDisposed) {
      return Future<AudioTurnLease>.error(const AudioTurnCoordinatorDisposed());
    }

    final request = _PendingAudioTurn(
      id: ++_nextRequestId,
      owner: owner,
      mode: mode,
      cancellation: cancellation,
    );
    _emit(AudioTurnDiagnosticType.acquireRequested, request: request);
    _pending.add(request);

    if (cancellation != null) {
      void cancelRequest() => _cancelPending(request);
      request.cancellationListener = cancelRequest;
      cancellation._addListener(cancelRequest);
    }
    if (timeout != null) {
      request.timeoutTimer = Timer(
        timeout,
        () => _timeoutPending(request, timeout),
      );
    }

    _drain();
    return request.completer.future;
  }

  Future<void> _release(AudioTurnToken token) async {
    final current = _current;
    if (current == null || current.token != token) {
      _emitForToken(
        AudioTurnDiagnosticType.staleRelease,
        token,
        message: 'The lease no longer owns the active audio turn.',
      );
      return;
    }

    _current = null;
    _emitForToken(AudioTurnDiagnosticType.released, token);
    _drain();
  }

  Future<AudioTurnLease?> _transfer({
    required AudioTurnToken from,
    required AudioTurnOwner owner,
    required AudioTurnMode mode,
  }) async {
    final current = _current;
    if (current == null || current.token != from || _isDisposed) {
      _emitForToken(
        AudioTurnDiagnosticType.staleRelease,
        from,
        message: 'A stale lease cannot transfer the active audio turn.',
      );
      return null;
    }

    final token = AudioTurnToken(
      id: ++_nextRequestId,
      generation: ++_generation,
      owner: owner,
      mode: mode,
    );
    final lease = AudioTurnLease._(this, token);
    _current = lease;
    _emitForToken(
      AudioTurnDiagnosticType.transferred,
      token,
      message: 'Transferred from ${from.owner.name}/${from.mode.name}.',
    );
    return lease;
  }

  void _drain() {
    if (_isDisposed || _current != null) {
      return;
    }
    while (_pending.isNotEmpty) {
      final request = _pending.removeAt(0);
      if (request.completer.isCompleted) {
        request.disposeSignals();
        continue;
      }
      final token = AudioTurnToken(
        id: request.id,
        generation: ++_generation,
        owner: request.owner,
        mode: request.mode,
      );
      final lease = AudioTurnLease._(this, token);
      _current = lease;
      request.disposeSignals();
      _emit(AudioTurnDiagnosticType.acquired, request: request, token: token);
      request.completer.complete(lease);
      return;
    }
  }

  void _cancelPending(_PendingAudioTurn request) {
    if (request.completer.isCompleted || !_pending.remove(request)) {
      return;
    }
    request.disposeSignals();
    _emit(AudioTurnDiagnosticType.cancelled, request: request);
    request.completer.completeError(const AudioTurnAcquireCancelled());
    _drain();
  }

  void _timeoutPending(_PendingAudioTurn request, Duration timeout) {
    if (request.completer.isCompleted || !_pending.remove(request)) {
      return;
    }
    request.disposeSignals();
    _emit(
      AudioTurnDiagnosticType.timedOut,
      request: request,
      message: timeout.toString(),
    );
    request.completer.completeError(AudioTurnAcquireTimeout(timeout));
    _drain();
  }

  void _emit(
    AudioTurnDiagnosticType type, {
    required _PendingAudioTurn request,
    AudioTurnToken? token,
    String? message,
  }) {
    if (_diagnostics.isClosed) {
      return;
    }
    _diagnostics.add(
      AudioTurnDiagnostic(
        type: type,
        owner: request.owner,
        mode: request.mode,
        requestId: request.id,
        token: token,
        message: message,
      ),
    );
  }

  void _emitForToken(
    AudioTurnDiagnosticType type,
    AudioTurnToken token, {
    String? message,
  }) {
    if (_diagnostics.isClosed) {
      return;
    }
    _diagnostics.add(
      AudioTurnDiagnostic(
        type: type,
        owner: token.owner,
        mode: token.mode,
        requestId: token.id,
        token: token,
        message: message,
      ),
    );
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    final pending = List<_PendingAudioTurn>.of(_pending);
    _pending.clear();
    for (final request in pending) {
      request.disposeSignals();
      if (!request.completer.isCompleted) {
        _emit(AudioTurnDiagnosticType.coordinatorDisposed, request: request);
        request.completer.completeError(const AudioTurnCoordinatorDisposed());
      }
    }
    _current = null;
    await _diagnostics.close();
  }
}

/// Compatibility wrapper used to adopt the coordinator one existing operation
/// at a time without changing the wrapped implementation or its call timing.
class CompatibilityAudioTurnAdapter {
  CompatibilityAudioTurnAdapter({
    required AudioTurnCoordinator coordinator,
    required AudioTurnOwner owner,
  }) : _coordinator = coordinator,
       _owner = owner;

  final AudioTurnCoordinator _coordinator;
  final AudioTurnOwner _owner;
  final AudioTurnCancellation _pendingCancellation = AudioTurnCancellation();
  final Set<AudioTurnLease> _leases = <AudioTurnLease>{};
  bool _isDisposed = false;

  Future<T> run<T>({
    required AudioTurnMode mode,
    required Future<T> Function(AudioTurnLease lease) action,
    Duration? acquireTimeout,
  }) async {
    if (_isDisposed) {
      throw const AudioTurnCoordinatorDisposed();
    }
    final lease = await _coordinator.acquire(
      owner: _owner,
      mode: mode,
      timeout: acquireTimeout,
      cancellation: _pendingCancellation,
    );
    if (_isDisposed) {
      await lease.release();
      throw const AudioTurnCoordinatorDisposed();
    }
    _leases.add(lease);
    try {
      return await action(lease);
    } finally {
      _leases.remove(lease);
      await lease.release();
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _pendingCancellation.cancel();
    final leases = List<AudioTurnLease>.of(_leases);
    _leases.clear();
    for (final lease in leases) {
      await lease.release();
    }
  }
}

class _PendingAudioTurn {
  _PendingAudioTurn({
    required this.id,
    required this.owner,
    required this.mode,
    required this.cancellation,
  });

  final int id;
  final AudioTurnOwner owner;
  final AudioTurnMode mode;
  final AudioTurnCancellation? cancellation;
  final Completer<AudioTurnLease> completer = Completer<AudioTurnLease>();
  void Function()? cancellationListener;
  Timer? timeoutTimer;

  void disposeSignals() {
    timeoutTimer?.cancel();
    timeoutTimer = null;
    final listener = cancellationListener;
    if (listener != null) {
      cancellation?._removeListener(listener);
      cancellationListener = null;
    }
  }
}
