import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:pneumonia_detection/main.dart';

void main() {
  setupFirebaseCoreMocks();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();
  });

  testWidgets('App launches with splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PneumoScanApp());

    expect(find.text('OmniSense AI'), findsOneWidget);
    expect(find.text('AI-Powered Health Assistant Detection'), findsOneWidget);

    // Flush splash navigation timer
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
  });
}
