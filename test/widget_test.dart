import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:podchain_demo_app/screens/login_screen.dart';
import 'package:podchain_demo_app/services/api_service.dart';

void main() {
  testWidgets(
      'login screen offers built-in test riders before backend registration',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<ApiService>.value(
        value: _FakeApiService(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Delivery Agent\nSign In'), findsOneWidget);
    expect(find.text('Aisha Mohammed'), findsOneWidget);
    expect(find.textContaining('creates test rider'), findsWidgets);
  });
}

class _FakeApiService extends ApiService {
  _FakeApiService() : super(baseUrl: 'http://127.0.0.1:3000');

  @override
  Future<List<String>> getRegisteredRiders() async => [];
}
