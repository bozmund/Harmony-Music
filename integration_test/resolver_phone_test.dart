import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = String.fromEnvironment('RESOLVER_PHONE_TEST_URL');

  testWidgets('physical phone reaches Resolver readiness endpoint', (
    tester,
  ) async {
    if (baseUrl.isEmpty) {
      markTestSkipped(
        'Set RESOLVER_PHONE_TEST_URL to the laptop LAN URL for this manual test.',
      );
      return;
    }
    final response = await Dio().get<Map<String, dynamic>>(
      '$baseUrl/health/ready',
    );
    expect(response.statusCode, 200);
    expect(response.data?['status'], 'ready');
    expect(
      response.data?['dependencies'],
      containsPair('postgresql', 'healthy'),
    );
    expect(response.data?['dependencies'], containsPair('minio', 'healthy'));
    expect(response.data?['dependencies'], containsPair('valkey', 'healthy'));
  });
}
