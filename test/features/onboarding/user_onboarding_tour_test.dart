import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/user_onboarding_tour.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('walks through welcome, spotlight, and completion steps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TourTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Chào mừng'), findsOneWidget);
    expect(find.byKey(const Key('user-onboarding-skip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('user-onboarding-next')));
    await tester.pumpAndSettle();

    expect(find.text('BƯỚC 1/1'), findsOneWidget);
    expect(find.text('Nút micro'), findsOneWidget);
    expect(find.byKey(const Key('user-onboarding-previous')), findsOneWidget);

    await tester.tap(find.byKey(const Key('user-onboarding-next')));
    await tester.pumpAndSettle();

    expect(find.text('Hoàn tất'), findsOneWidget);
    expect(find.text('Thử nói ngay'), findsOneWidget);
    expect(find.byKey(const Key('user-onboarding-skip')), findsNothing);
  });

  testWidgets('skip action closes the tour', (tester) async {
    await tester.pumpWidget(const _TourTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('user-onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('user-onboarding-tour')), findsNothing);
  });
}

class _TourTestApp extends StatelessWidget {
  const _TourTestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const DisplayLanguageScope(
        language: DisplayLanguage.vietnamese,
        child: _TourHarness(),
      ),
    );
  }
}

class _TourHarness extends StatefulWidget {
  const _TourHarness();

  @override
  State<_TourHarness> createState() => _TourHarnessState();
}

class _TourHarnessState extends State<_TourHarness> {
  final GlobalKey _targetKey = GlobalKey();
  int _index = 0;
  bool _visible = true;

  List<UserOnboardingStep> get _steps => <UserOnboardingStep>[
    const UserOnboardingStep(
      kind: UserOnboardingStepKind.welcome,
      title: 'Chào mừng',
      description: 'Làm quen nhanh với ứng dụng.',
      icon: Icons.waving_hand_rounded,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: 'Nút micro',
      description: 'Chạm vào đây để bắt đầu nói.',
      icon: Icons.mic_rounded,
      targetKey: _targetKey,
    ),
    const UserOnboardingStep(
      kind: UserOnboardingStepKind.complete,
      title: 'Hoàn tất',
      description: 'Bạn đã sẵn sàng.',
      icon: Icons.celebration_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: FilledButton(
              key: _targetKey,
              onPressed: () {},
              child: const Text('Micro'),
            ),
          ),
          if (_visible)
            UserOnboardingTour(
              steps: _steps,
              currentIndex: _index,
              onPrevious: _index == 0
                  ? null
                  : () => setState(() => _index -= 1),
              onNext: () {
                if (_index == _steps.length - 1) {
                  setState(() => _visible = false);
                } else {
                  setState(() => _index += 1);
                }
              },
              onSkip: () => setState(() => _visible = false),
            ),
        ],
      ),
    );
  }
}
