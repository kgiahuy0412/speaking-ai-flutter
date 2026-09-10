import 'package:ai_speaking_flutter_app/features/listening/data/active_listening_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('round-trips the active lesson route checkpoint', () async {
    const store = ActiveListeningSessionStore();

    await store.save(childAge: 8, topicNumber: 3, lessonNumber: 2);
    final checkpoint = await store.read();

    expect(checkpoint, isNotNull);
    expect(checkpoint?.childAge, 8);
    expect(checkpoint?.topicNumber, 3);
    expect(checkpoint?.lessonNumber, 2);
    expect(checkpoint?.updatedAtEpochMs, greaterThan(0));
  });

  test(
    'clear prevents a completed or exited route from being restored',
    () async {
      const store = ActiveListeningSessionStore();
      await store.save(childAge: 11, topicNumber: 4, lessonNumber: 1);

      await store.clear();

      expect(await store.read(), isNull);
    },
  );

  test('ignores a malformed checkpoint', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'active-listening-session-v1',
      '{"childAge":0,"topicNumber":2}',
    );

    expect(await const ActiveListeningSessionStore().read(), isNull);
  });
}
