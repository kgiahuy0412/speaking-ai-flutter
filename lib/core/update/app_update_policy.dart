class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.latestVersion,
    required this.latestBuild,
    required this.minimumSupportedBuild,
    required this.downloadUrl,
    required this.vietnameseMessage,
    required this.chineseMessage,
  });

  factory AppUpdatePolicy.fromJson(Map<String, dynamic> json) {
    final latestVersion = '${json['latestVersion'] ?? ''}'.trim();
    final latestBuild = (json['latestBuild'] as num?)?.toInt();
    final minimumSupportedBuild = (json['minimumSupportedBuild'] as num?)
        ?.toInt();
    final downloadUrl = Uri.tryParse('${json['downloadUrl'] ?? ''}'.trim());
    final messages = json['messages'];
    final messageMap = messages is Map
        ? Map<String, dynamic>.from(messages)
        : const <String, dynamic>{};
    final vietnameseMessage = '${messageMap['vi'] ?? ''}'.trim();
    final chineseMessage = '${messageMap['zh'] ?? ''}'.trim();

    if (latestVersion.isEmpty ||
        latestBuild == null ||
        latestBuild < 1 ||
        minimumSupportedBuild == null ||
        minimumSupportedBuild < 1 ||
        minimumSupportedBuild > latestBuild ||
        downloadUrl == null ||
        downloadUrl.scheme != 'https' ||
        vietnameseMessage.isEmpty ||
        chineseMessage.isEmpty) {
      throw const FormatException('Invalid Android app update policy.');
    }

    return AppUpdatePolicy(
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      minimumSupportedBuild: minimumSupportedBuild,
      downloadUrl: downloadUrl,
      vietnameseMessage: vietnameseMessage,
      chineseMessage: chineseMessage,
    );
  }

  final String latestVersion;
  final int latestBuild;
  final int minimumSupportedBuild;
  final Uri downloadUrl;
  final String vietnameseMessage;
  final String chineseMessage;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'latestVersion': latestVersion,
    'latestBuild': latestBuild,
    'minimumSupportedBuild': minimumSupportedBuild,
    'downloadUrl': downloadUrl.toString(),
    'messages': <String, String>{'vi': vietnameseMessage, 'zh': chineseMessage},
  };
}

enum AppUpdatePolicySource { network, cache, unavailable }

class AppUpdateDecision {
  const AppUpdateDecision({
    required this.currentBuild,
    required this.policy,
    required this.source,
  });

  const AppUpdateDecision.unavailable()
    : currentBuild = null,
      policy = null,
      source = AppUpdatePolicySource.unavailable;

  final int? currentBuild;
  final AppUpdatePolicy? policy;
  final AppUpdatePolicySource source;

  bool get requiresUpdate {
    final current = currentBuild;
    final value = policy;
    return current != null &&
        value != null &&
        current < value.minimumSupportedBuild;
  }

  bool get updateAvailable {
    final current = currentBuild;
    final value = policy;
    return current != null && value != null && current < value.latestBuild;
  }
}
