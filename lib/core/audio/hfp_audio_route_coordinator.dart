import 'dart:async';

import 'audio_input.dart';
import 'hfp_audio_control.dart';

class HfpAudioRouteToken {
  const HfpAudioRouteToken({
    required this.id,
    required this.generation,
    required this.owner,
  });

  final int id;
  final int generation;
  final String owner;

  @override
  bool operator ==(Object other) =>
      other is HfpAudioRouteToken &&
      other.id == id &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(id, generation);
}

/// Optional ownership capability exposed by a scoped HFP control.
abstract interface class HfpAudioRouteLeaseControl {
  HfpAudioRouteToken? get activeAudioRouteToken;

  /// Drops this Dart owner after a native recognizer has assumed ownership of
  /// the already-open route. It deliberately does not close SCO/HFP.
  Future<void> handoffAudioRoute();
}

/// One process-level writer for the native HFP/SCO route.
///
/// Each feature receives a [ScopedHfpAudioControl]. The first scope opens the
/// native route and the final scope closes it, so disposing an older feature
/// cannot tear down a newer feature's microphone or playback route.
class HfpAudioRouteCoordinator {
  HfpAudioRouteCoordinator(this._delegate);

  final HfpAudioControl _delegate;
  final Map<int, HfpAudioRouteToken> _active = <int, HfpAudioRouteToken>{};
  Future<void> _operationTail = Future<void>.value();
  int _nextId = 0;
  int _generation = 0;
  bool _disposed = false;

  HfpAudioControl createScope(String owner) =>
      ScopedHfpAudioControl._(this, owner.trim().isEmpty ? 'unknown' : owner);

  Future<HfpAudioRouteToken> _acquire(String owner) {
    return _serialize(() async {
      _ensureActive();
      if (_active.isEmpty) {
        await _delegate.startAudioRoute();
      }
      final token = HfpAudioRouteToken(
        id: ++_nextId,
        generation: ++_generation,
        owner: owner,
      );
      _active[token.id] = token;
      return token;
    });
  }

  Future<bool> _revalidate(HfpAudioRouteToken token) {
    return _serialize(() async {
      if (_disposed || _active[token.id] != token) {
        return false;
      }
      await _delegate.startAudioRoute();
      return true;
    });
  }

  Future<void> _release(HfpAudioRouteToken token) {
    return _serialize(() async {
      if (_disposed || _active[token.id] != token) {
        return;
      }
      _active.remove(token.id);
      if (_active.isEmpty) {
        await _delegate.stopAudioRoute();
      }
    });
  }

  Future<void> _handoff(HfpAudioRouteToken token) {
    return _serialize(() async {
      if (_disposed || _active[token.id] != token) {
        return;
      }
      _active.remove(token.id);
      // Native Apple Speech/HFP has already opened and retained its own owner.
      // Closing here would recreate the prompt-to-micro route gap.
    });
  }

  Future<void> disconnect() {
    return _serialize(() async {
      _active.clear();
      if (!_disposed) {
        await _delegate.disconnect();
      }
    });
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _operationTail.then<T>((_) => action());
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('HFP audio route coordinator has been disposed.');
    }
  }

  Future<void> dispose() {
    return _serialize(() async {
      if (_disposed) {
        return;
      }
      _disposed = true;
      final hadActiveRoute = _active.isNotEmpty;
      _active.clear();
      if (hadActiveRoute) {
        await _delegate.stopAudioRoute().catchError((Object _) {});
      }
      await _delegate.dispose();
    });
  }
}

class ScopedHfpAudioControl
    implements HfpAudioControl, HfpAudioRouteLeaseControl {
  ScopedHfpAudioControl._(this._coordinator, this.owner);

  final HfpAudioRouteCoordinator _coordinator;
  final String owner;
  HfpAudioRouteToken? _token;
  bool _disposed = false;

  HfpAudioControl get _delegate => _coordinator._delegate;

  @override
  HfpAudioRouteToken? get activeAudioRouteToken => _token;

  @override
  bool get usesBrowserAudioInput => _delegate.usesBrowserAudioInput;

  @override
  BluetoothAudioStatus get status => _delegate.status;

  @override
  Stream<BluetoothAudioStatus> get statusChanges => _delegate.statusChanges;

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  Future<List<HfpAudioDevice>> findDevices() => _delegate.findDevices();

  @override
  Future<void> connect(HfpAudioDevice device) => _delegate.connect(device);

  @override
  Future<void> disconnect() async {
    _token = null;
    await _coordinator.disconnect();
  }

  @override
  Future<void> startAudioRoute() async {
    if (_disposed) {
      throw StateError('Scoped HFP audio control has been disposed.');
    }
    final token = _token;
    if (token != null) {
      if (await _coordinator._revalidate(token)) {
        return;
      }
      _token = null;
    }
    _token = await _coordinator._acquire(owner);
  }

  @override
  Future<void> stopAudioRoute() async {
    final token = _token;
    _token = null;
    if (token != null) {
      await _coordinator._release(token);
    }
  }

  @override
  Future<void> handoffAudioRoute() async {
    final token = _token;
    _token = null;
    if (token != null) {
      await _coordinator._handoff(token);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stopAudioRoute();
  }
}
