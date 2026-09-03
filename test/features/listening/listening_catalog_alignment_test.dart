import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('journey catalog mirrors V4 topic names and lesson totals', () async {
    final content = await AssetListeningContentRepository().load();

    expect(listeningCatalogs, hasLength(content.groups.length));
    expect(
      listeningCatalogs.expand((catalog) => catalog.topics),
      hasLength(50),
    );

    for (final catalog in listeningCatalogs) {
      final publishedGroup = content.groups.singleWhere(
        (group) =>
            group.startAge == catalog.startAge &&
            group.endAge == catalog.endAge,
      );
      expect(catalog.topics, hasLength(publishedGroup.topics.length));
      expect(catalog.continueTopicIndex, 0);

      for (var index = 0; index < catalog.topics.length; index += 1) {
        final journeyTopic = catalog.topics[index];
        final publishedTopic = publishedGroup.topics[index];

        expect(journeyTopic.titleVi, publishedTopic.titleVi);
        expect(journeyTopic.total, publishedTopic.lessons.length);
        expect(journeyTopic.completed, 0);
        expect(journeyTopic.imagePath, isNotNull);
      }
    }
  });
}
