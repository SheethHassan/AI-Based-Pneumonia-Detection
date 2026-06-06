import 'package:flutter_test/flutter_test.dart';
import 'package:pneumonia_detection/main.dart';

void main() {
  testWidgets('App launches with splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PneumoScanApp());

    // Verify splash screen elements
    expect(find.text('PneumoScan AI'), findsOneWidget);
    expect(find.text('AI-Powered Pneumonia Detection'), findsOneWidget);
  });
}
