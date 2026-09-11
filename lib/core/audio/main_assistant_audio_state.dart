import 'package:flutter/foundation.dart';

/// Read-only conversation audio state required by the floating MAIN control.
///
/// Keeping this contract in core prevents voice-navigation presentation from
/// depending on the concrete conversation presentation controller.
abstract interface class MainAssistantAudioState implements Listenable {
  bool get isBusy;
  bool get isPlaybackPlaying;
  bool get isPreparingMicrophone;
}
