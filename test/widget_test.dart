import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:right_answer/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RightAnswerApp());
    await tester.pump();

    expect(find.byType(RightAnswerApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}