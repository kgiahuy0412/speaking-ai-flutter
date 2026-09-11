import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_architecture_boundaries.dart' as architecture;

void main() {
  test('feature and audio boundaries remain isolated', () {
    final violations = architecture.checkArchitectureBoundaries(
      Directory.current,
    );

    expect(
      violations,
      isEmpty,
      reason: violations.map((violation) => violation.toString()).join('\n'),
    );
  });
}
