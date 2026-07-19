import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:right_answer/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RightAnswerApp(showOnboarding: false));
    await tester.pump();

    expect(find.byType(RightAnswerApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
