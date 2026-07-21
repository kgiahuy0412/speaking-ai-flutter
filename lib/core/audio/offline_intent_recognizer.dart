import 'dart:async';
import 'package:flutter/services.dart';

class OfflineIntentDefinition {
  const OfflineIntentDefinition({
    required this.id,
    required this.contexts,
    required this.samples,
    required this.englishText,
    required this.audioUri,
  });

  factory OfflineIntentDefinition.fromJson(
    Map<String, dynamic> json, {
    required Uri backendBaseUri,
  }) {
    return OfflineIntentDefinition(
      id: json['id'] as String? ?? '',
      contexts: (json['contexts'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      samples: (json['samples'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      englishText: json['englishText'] as String? ?? '',
      audioUri: backendBaseUri.resolve(json['audioUrl'] as String? ?? ''),
    );
  }

  final String id;
  final List<String> contexts;
  final List<String> samples;
  final String englishText;
  final Uri audioUri;

  Map<String, dynamic> toNativeJson() => <String, dynamic>{
    'id': id,
    'contexts': contexts,
    'samples': samples,
  };
}

class OfflineIntentPolicy {
  const OfflineIntentPolicy({
    required this.confidenceThreshold,
    required this.marginThreshold,
    required this.stableUpdates,
    required this.earlyFallbackMs,
  });

  factory OfflineIntentPolicy.fromJson(Map<String, dynamic> json) {
    return OfflineIntentPolicy(
      confidenceThreshold:
          (json['confidenceThreshold'] as num?)?.toDouble() ?? 0.88,
      marginThreshold: (json['marginThreshold'] as num?)?.toDouble() ?? 0.15,
      stableUpdates: (json['stableUpdates'] as num?)?.round() ?? 3,
      earlyFallbackMs: (json['earlyFallbackMs'] as num?)?.round() ?? 800,
    );
  }

  final double confidenceThreshold;
  final double marginThreshold;
  final int stableUpdates;
  final int earlyFallbackMs;
}

class OfflineIntentManifest {
  const OfflineIntentManifest({
    required this.version,
    required this.sampleRate,
    required this.policy,
    required this.items,
  });

  factory OfflineIntentManifest.fromJson(
    Map<String, dynamic> json, {
    required Uri backendBaseUri,
  }) {
    final rawPolicy = json['policy'];
    return OfflineIntentManifest(
      version: json['version'] as String? ?? 'unknown',
      sampleRate: (json['sampleRate'] as num?)?.round() ?? 24000,
      policy: OfflineIntentPolicy.fromJson(
        rawPolicy is Map<String, dynamic>
            ? rawPolicy
            : const <String, dynamic>{},
      ),
      items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => OfflineIntentDefinition.fromJson(
              item,
              backendBaseUri: backendBaseUri,
            ),
          )
          .where((item) => item.id.isNotEmpty && item.samples.isNotEmpty)
          .toList(growable: false),
    );
  }

  final String version;
  final int sampleRate;
  final OfflineIntentPolicy policy;
  final List<OfflineIntentDefinition> items;
}

class OfflineIntentAlternative {
  const OfflineIntentAlternative({
    required this.intentId,
    required this.confidence,
  });

  factory OfflineIntentAlternative.fromJson(Map<String, dynamic> json) {
    return OfflineIntentAlternative(
      intentId: json['intentId'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  final String intentId;
  final double confidence;
}

class OfflineIntentHypothesis {
  const OfflineIntentHypothesis({
    required this.intentId,
    required this.transcript,
    required this.confidence,
    this.alternatives = const <OfflineIntentAlternative>[],
    this.isUnknown = false,
  });

  factory OfflineIntentHypothesis.fromJson(Map<String, dynamic> json) {
    return OfflineIntentHypothesis(
      intentId: json['intentId'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      alternatives:
          (json['alternatives'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(OfflineIntentAlternative.fromJson)
              .toList(growable: false),
      isUnknown: json['unknown'] as bool? ?? false,
    );
  }

  final String intentId;
  final String transcript;
  final double confidence;
  final List<OfflineIntentAlternative> alternatives;
  final bool isUnknown;
}

class OfflineIntentDecision {
  const OfflineIntentDecision({required this.hypothesis, required this.margin});

  final OfflineIntentHypothesis hypothesis;
  final double margin;
}

class OfflineIntentGate {
  OfflineIntentGate(this.policy);

  final OfflineIntentPolicy policy;
  String? _candidateId;
  int _stableUpdates = 0;

  OfflineIntentDecision? evaluate(OfflineIntentHypothesis hypothesis) {
    final runnerUp = hypothesis.alternatives
        .where((item) => item.intentId != hypothesis.intentId)
        .fold<double>(
          0,
          (best, item) => item.confidence > best ? item.confidence : best,
        );
    final margin = hypothesis.confidence - runnerUp;
    final eligible =
        !hypothesis.isUnknown &&
        hypothesis.intentId.isNotEmpty &&
        hypothesis.transcript.trim().isNotEmpty &&
        hypothesis.confidence >= policy.confidenceThreshold &&
        margin >= policy.marginThreshold;

    if (!eligible) {
      reset();
      return null;
    }

    if (_candidateId == hypothesis.intentId) {
      _stableUpdates += 1;
    } else {
      _candidateId = hypothesis.intentId;
      _stableUpdates = 1;
    }

    if (_stableUpdates < policy.stableUpdates) {
      return null;
    }
    return OfflineIntentDecision(hypothesis: hypothesis, margin: margin);
  }

  void reset() {
    _candidateId = null;
    _stableUpdates = 0;
  }
}

abstract interface class OfflineIntentRecognizer {
  Stream<OfflineIntentHypothesis> get hypotheses;

  Future<bool> checkAvailability();

  Future<void> start({required OfflineIntentManifest manifest});

  void addAudioChunk(Uint8List bytes);

  Future<OfflineIntentHypothesis?> stop();

  Future<void> cancel();

  Future<void> dispose();
}

class MethodChannelOfflineIntentRecognizer implements OfflineIntentRecognizer {
  MethodChannelOfflineIntentRecognizer({
    MethodChannel controlChannel = const MethodChannel(
      'ailingo_offline_intent',
    ),
    EventChannel eventChannel = const EventChannel(
      'ailingo_offline_intent/events',
    ),
    BasicMessageChannel<ByteData?> pcmChannel =
        const BasicMessageChannel<ByteData?>(
          'ailingo_offline_intent/pcm',
          BinaryCodec(),
        ),
  }) : _controlChannel = controlChannel,
       _eventChannel = eventChannel,
       _pcmChannel = pcmChannel;

  final MethodChannel _controlChannel;
  final EventChannel _eventChannel;
  final BasicMessageChannel<ByteData?> _pcmChannel;
  Stream<OfflineIntentHypothesis>? _hypotheses;

  @override
  Stream<OfflineIntentHypothesis> get hypotheses =>
      _hypotheses ??= _eventChannel
          .receiveBroadcastStream()
          .where((event) => event is Map)
          .map(
            (event) => OfflineIntentHypothesis.fromJson(
              Map<String, dynamic>.from(event as Map<dynamic, dynamic>),
            ),
          );

  @override
  Future<bool> checkAvailability() async {
    try {
      return await _controlChannel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> start({required OfflineIntentManifest manifest}) async {
    await _controlChannel.invokeMethod<void>('start', <String, dynamic>{
      'version': manifest.version,
      'sampleRate': manifest.sampleRate,
      'intents': manifest.items.map((item) => item.toNativeJson()).toList(),
    });
  }

  @override
  void addAudioChunk(Uint8List bytes) {
    if (bytes.isEmpty) {
      return;
    }
    unawaited(
      _pcmChannel
          .send(ByteData.sublistView(bytes))
          .catchError((Object _) => null),
    );
  }

  @override
  Future<OfflineIntentHypothesis?> stop() async {
    final result = await _controlChannel.invokeMethod<dynamic>('stop');
    if (result is! Map) {
      return null;
    }
    return OfflineIntentHypothesis.fromJson(Map<String, dynamic>.from(result));
  }

  @override
  Future<void> cancel() async {
    await _controlChannel.invokeMethod<void>('cancel');
  }

  @override
  Future<void> dispose() async {
    try {
      await _controlChannel.invokeMethod<void>('dispose');
    } on MissingPluginException {
      // Native bridge is intentionally optional until the BLE model is added.
    }
  }
}
