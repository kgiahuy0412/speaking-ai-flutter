import 'vocabulary_entry.dart';

enum VocabularyJourneyKind { parentAdded, review, stars }

enum VocabularyPlaybackScope { latest, all }

/// Exact child-facing copy and deterministic rules from Vocabulary FINAL V3.
///
/// Keeping these rules outside the widgets prevents the Android and iOS paths
/// from drifting when they use different microphone implementations.
abstract final class VocabularyFlowV3 {
  static const int groupSize = 5;

  static const String todayIntro =
      'Đã có nội dung mới cho bạn. Bắt đầu học thôi!';
  static const String menu =
      'Bạn muốn học Ba mẹ đã thêm, Luyện lại hay Ngôi sao?';
  static const String todayEmptyMenu =
      'Hôm nay chưa có nội dung mới. Bạn muốn học Ba mẹ đã thêm, Luyện lại hay Ngôi sao?';
  static const String finishActiveGroupFirst =
      'Mình học xong lượt này trước nhé.';

  static const String todayCompletion =
      'Bạn muốn học tiếp hay học nội dung khác?';
  static const String todayQueueEmpty =
      'Không còn nội dung mới nữa. Bạn muốn học Ba mẹ đã thêm, Luyện lại hay Ngôi sao?';

  static const String parentScopeChoice =
      'Bạn muốn nghe nội dung mới nhất hay nghe lại tất cả?';
  static const String parentSmallIntro = 'Mình cùng nghe nhé.';
  static const String parentEmpty =
      'Chưa có nội dung ở phần này. Bạn muốn học Luyện lại hay Ngôi sao?';
  static const String parentSpeakAgainGuide =
      'Nếu có câu muốn luyện lại, bạn nhấn nút rồi đọc “Nói lại” nhé.';
  static const String startPlayback = 'Bắt đầu nào.';
  static const String parentGroupCompletion =
      'Bạn muốn nghe tiếp hay học nội dung khác?';
  static const String parentOtherMenu = 'Bạn muốn học Luyện lại hay Ngôi sao?';
  static const String parentFinished =
      'Bạn đã nghe hết nội dung rồi. Bạn muốn học Luyện lại hay Ngôi sao?';

  static const String reviewIntro = 'Mình cùng luyện lại nhé. Bắt đầu thôi!';
  static const String reviewGroupCompletion =
      'Bạn muốn luyện tiếp hay học nội dung khác?';
  static const String reviewOtherMenu =
      'Bạn muốn học Ba mẹ đã thêm hay Ngôi sao?';
  static const String reviewCycleFinished =
      'Mình đã luyện hết lượt này rồi. Bạn muốn học Ba mẹ đã thêm hay Ngôi sao?';
  static const String reviewEmpty =
      'Không còn nội dung cần luyện lại. Bạn muốn học Ba mẹ đã thêm hay Ngôi sao?';

  static String starScopeChoice(int total) =>
      'Bạn đang có $total Ngôi sao. Bạn muốn nghe Ngôi sao mới nhất hay nghe lại tất cả?';

  static String starSmallIntro(int total) =>
      'Bạn đang có $total Ngôi sao. Mình cùng nghe nhé.';

  static const String starEmpty =
      'Bạn chưa có Ngôi sao nào. Bạn muốn học Ba mẹ đã thêm hay Luyện lại?';
  static const String starVoiceIntro = 'Giọng của bạn đây.';
  static const String starGroupCompletion =
      'Bạn muốn nghe thêm hay học nội dung khác?';
  static const String starOtherMenu =
      'Bạn muốn học Ba mẹ đã thêm hay Luyện lại?';
  static const String starFinished =
      'Bạn đã nghe hết Ngôi sao rồi. Bạn muốn học Ba mẹ đã thêm hay Luyện lại?';
  static const String starScopeRetry =
      'Bạn chọn Ngôi sao mới nhất hoặc nghe lại tất cả nhé.';
  static const String stopHere = 'Mình dừng ở đây nhé.';
  static const String resumeStars = 'Mình nghe tiếp nhé.';
  static const String switchToLatestStars = 'Mình nghe Ngôi sao mới nhất nhé.';
  static const String switchToAllStars = 'Mình nghe lại tất cả nhé.';

  static const List<String> starNextCues = <String>[
    'Câu tiếp theo.',
    'Ngôi sao tiếp theo.',
    'Mình nghe tiếp nhé.',
    'Tiếp tục nào.',
    'Thêm một Ngôi sao nữa nhé.',
  ];

  static List<VocabularyEntry> orderedForPlayback(
    Iterable<VocabularyEntry> source, {
    required VocabularyJourneyKind journey,
    required VocabularyPlaybackScope scope,
  }) {
    final entries = source.toList(growable: false);
    entries.sort((left, right) {
      final leftTime = journey == VocabularyJourneyKind.stars
          ? left.earnedAt ?? left.addedAt
          : left.addedAt;
      final rightTime = journey == VocabularyJourneyKind.stars
          ? right.earnedAt ?? right.addedAt
          : right.addedAt;
      return scope == VocabularyPlaybackScope.latest
          ? rightTime.compareTo(leftTime)
          : leftTime.compareTo(rightTime);
    });
    return entries;
  }

  /// Alphabet targets are authored as "A. Apple." but V3 also accepts the
  /// spoken keyword "Apple". Parent-authored text never receives this rewrite.
  static List<String> acceptedVariantsFor(VocabularyEntry entry) {
    if (entry.source == VocabularySource.parent) {
      return const <String>[];
    }
    final match = RegExp(
      r'^\s*[A-Za-z]\s*[.:-]\s*(.+?)\s*$',
    ).firstMatch(entry.word);
    final keyword = match?.group(1)?.trim() ?? '';
    return keyword.isEmpty ? const <String>[] : <String>[keyword];
  }
}
