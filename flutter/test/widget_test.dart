import 'package:flutter_test/flutter_test.dart';

import 'package:deauther/main.dart';

void main() {
  testWidgets('app boots into scan screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DeautherApp());
    await tester.pump();
    expect(find.text('ESP32-C5 Deauther'), findsOneWidget);
  });
}
