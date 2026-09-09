import 'package:ai_speaking_flutter_app/features/conversation/application/vietnamese_transcript_corrector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Vietnamese transcript correction', () {
    test('normalizes casing, punctuation, and repeated whitespace', () {
      expect(
        normalizeVietnameseTranscript('  BÓ ơi,   con buồn ngủ!!! '),
        'bó ơi con buồn ngủ',
      );
    });

    test('loads a reviewed speech-impediment pair from the asset', () async {
      final corrector = AssetVietnameseTranscriptCorrector();
      await corrector.warmUp();

      final correction = await corrector.correct(
        primaryText: '  con NGỬA tay xong rồi! ',
      );

      expect(correction.wasCorrected, isTrue);
      expect(correction.correctedText, 'Con rửa tay xong rồi');
    });

    test(
      'uses a recognizer alternative when the primary has no match',
      () async {
        final corrector = MapVietnameseTranscriptCorrector(<String, String>{
          'Con nặng quá': 'Con lạnh quá',
        });

        final correction = await corrector.correct(
          primaryText: 'Con lạ quá',
          alternatives: const <String>['Con nặng quá.'],
        );

        expect(correction.matchedText, 'Con nặng quá.');
        expect(correction.correctedText, 'Con lạnh quá');
        expect(correction.wasCorrected, isTrue);
      },
    );

    test('does not fuzzy-match a longer ordinary sentence', () async {
      final corrector = MapVietnameseTranscriptCorrector(<String, String>{
        'Con nặng quá': 'Con lạnh quá',
      });

      final correction = await corrector.correct(
        primaryText: 'Chiếc cặp của con nặng quá',
      );

      expect(correction.wasCorrected, isFalse);
      expect(correction.correctedText, 'Chiếc cặp của con nặng quá');
    });

    test('keeps a rejected bad workbook row unchanged', () async {
      final corrector = AssetVietnameseTranscriptCorrector();

      final correction = await corrector.correct(primaryText: 'Chào tạm biệt.');

      expect(correction.wasCorrected, isFalse);
      expect(correction.correctedText, 'Chào tạm biệt.');
    });
  });
}
