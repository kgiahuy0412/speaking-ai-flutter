class PwaRuntimeState {
  const PwaRuntimeState({
    required this.installRequired,
    required this.inAppBrowser,
  });

  final bool installRequired;
  final bool inAppBrowser;
}

PwaRuntimeState readPwaRuntimeState() =>
    const PwaRuntimeState(installRequired: false, inAppBrowser: false);
