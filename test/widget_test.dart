import 'package:flutter_test/flutter_test.dart';

import 'package:techzakaz_driver_app/main.dart';

void main() {
  testWidgets('TechZakaz driver app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const TechZakazDriverApp());

    expect(find.text('ТехЗаказ Водитель'), findsOneWidget);
  });
}
