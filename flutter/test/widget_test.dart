import 'package:deauther/main.dart';
import 'package:deauther/services/api_server.dart';
import 'package:deauther/services/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots into scan screen', (WidgetTester tester) async {
    final settings = Settings();
    final api = ApiServer(settings);
    await tester.pumpWidget(DeautherApp(settings: settings, api: api));
    await tester.pump();
    expect(find.text('ESP32-C5 Deauther'), findsOneWidget);
  });
}
