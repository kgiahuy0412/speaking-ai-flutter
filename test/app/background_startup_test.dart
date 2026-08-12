import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shares the bundled listening catalog background preload', (
    tester,
  ) async {
    final firstRepository = AssetListeningContentRepository();
    final secondRepository = AssetListeningContentRepository();

    final firstLoad = firstRepository.load();
    final secondLoad = secondRepository.load();

    expect(identical(firstLoad, secondLoad), isTrue);
    final catalog = await firstLoad;
    expect(catalog.groups, isNotEmpty);
  });
}
