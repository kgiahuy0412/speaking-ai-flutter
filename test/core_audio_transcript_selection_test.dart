import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a longer partial when the final transcript is clearly cut', () {
    expect(
      preferCompleteVietnameseTranscript(
        partialText: 'Mẹ ơi có lẽ con muốn đi nhà trẻ',
        finalText: 'Mẹ ơi có lẽ con',
      ),
      'Mẹ ơi có lẽ con muốn đi nhà trẻ',
    );
  });

  test('trusts a complete final correction instead of a longer partial', () {
    expect(
      preferCompleteVietnameseTranscript(
        partialText: 'Mẹ ơi con muốn đi học ngày mai',
        finalText: 'Mẹ ơi con muốn đi học',
      ),
      'Mẹ ơi con muốn đi học',
    );
  });

  test('does not combine substantially different hypotheses', () {
    expect(
      preferCompleteVietnameseTranscript(
        partialText: 'Mẹ ơi cô la con nên con buồn lắm',
        finalText: 'Mẹ ơi con là con',
      ),
      'Mẹ ơi con là con',
    );
  });
}
