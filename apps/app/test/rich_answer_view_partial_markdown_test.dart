import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:right_answer/widgets/rich_answer_view.dart';

/// The streaming chat path feeds `RichAnswerView` (via `GptMarkdown`) the
/// *growing* accumulated answer on every chunk — meaning it renders every
/// intermediate, syntactically-incomplete state of the markdown, not just
/// the final valid document. This test simulates that by streaming a
/// realistic answer one character at a time and asserting no exception is
/// ever thrown mid-stream, plus a handful of specific malformed shapes
/// (unclosed bold, incomplete list item, half-finished table row, a heading
/// cut mid-line) called out explicitly in the streaming task spec.
void main() {
  Future<void> pumpContent(WidgetTester tester, String content) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichAnswerView(content: content, isDark: false),
        ),
      ),
    );
  }

  testWidgets(
    'GptMarkdown renders every prefix of a streamed answer without throwing',
    (tester) async {
      const fullAnswer =
          '## Heading\n\n'
          'This is **bold text** and *italic text* with `inline code`.\n\n'
          '- First bullet\n'
          '- Second bullet with **bold**\n'
          '- Third\n\n'
          '| Col A | Col B |\n'
          '|-------|-------|\n'
          '| 1     | 2     |\n'
          '| 3     | 4     |\n\n'
          '1. Step one\n'
          '2. Step two\n\n'
          '> A blockquote\n\n'
          '```dart\n'
          'void main() {}\n'
          '```\n';

      // Stream in coarse steps (every 3 chars) rather than one-by-one to
      // keep the test fast while still hitting a very wide variety of
      // truncation points (mid-word, mid-token, mid-table-row, etc).
      for (var i = 1; i <= fullAnswer.length; i += 3) {
        final prefix = fullAnswer.substring(0, i);
        await pumpContent(tester, prefix);
        final exception = tester.takeException();
        expect(
          exception,
          isNull,
          reason:
              'GptMarkdown threw while rendering partial content:\n"$prefix"\n\nException: $exception',
        );
      }
    },
  );

  testWidgets('unclosed bold marker does not throw', (tester) async {
    await pumpContent(tester, 'This is **bold that never clo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete list item does not throw', (tester) async {
    await pumpContent(tester, 'Some intro text\n\n- First item\n- Sec');
    expect(tester.takeException(), isNull);
  });

  testWidgets('half-finished table row does not throw', (tester) async {
    await pumpContent(
      tester,
      '| Col A | Col B |\n|-------|-------|\n| val1  | va',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('heading cut mid-line does not throw', (tester) async {
    await pumpContent(tester, '## Head');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unclosed code fence does not throw', (tester) async {
    await pumpContent(tester, 'Some text\n\n```dart\nvoid main() {\n  pr');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and whitespace-only content does not throw', (
    tester,
  ) async {
    await pumpContent(tester, '');
    expect(tester.takeException(), isNull);
    await pumpContent(tester, '   \n  ');
    expect(tester.takeException(), isNull);
  });
}
