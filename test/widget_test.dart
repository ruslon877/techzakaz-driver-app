import 'package:flutter_test/flutter_test.dart';

import 'package:techzakaz_driver_app/main.dart';

void main() {
  test('TechZakaz driver app root is constructible', () {
    expect(const TechZakazDriverApp(), isA<TechZakazDriverApp>());
    expect(const FirebaseInitErrorScreen(error: 'test'), isA<FirebaseInitErrorScreen>());
  });
}
