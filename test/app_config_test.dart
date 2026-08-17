import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the production backend when no URL is supplied', () {
    final config = AppConfig.fromEnvironment();

    expect(
      config.backendBaseUri,
      Uri.parse(AppConfig.productionBackendBaseUrl),
    );
  });
}
