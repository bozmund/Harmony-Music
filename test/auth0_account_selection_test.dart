import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = File('lib/services/auth0_service.dart').readAsStringSync();

  test('account-switch login forces Auth0 reauthentication', () {
    expect(
      service,
      contains(
        'static const _accountSelectionLoginParameters = <String, String>{',
      ),
    );
    expect(service, contains("'prompt': 'login'"));
    expect(service, isNot(contains('ext-google-prompt')));
    expect(service, contains('final parameters = chooseAccount'));
    expect(
      RegExp(r'parameters:\s*parameters').allMatches(service),
      hasLength(2),
    );
  });

  test('ordinary login does not force account selection', () {
    expect(
      RegExp(
        r'chooseAccount\s*\?\s*_accountSelectionLoginParameters\s*'
        r':\s*const <String, String>\{\}',
      ).hasMatch(service),
      isTrue,
    );
  });

  test('ordinary logout stays scoped to the app', () {
    expect(service, isNot(contains('federated: true')));
  });

  test('session restoration diagnostics do not include exception contents', () {
    // Every restore-failure log must go through the redacting helper, passing
    // the caught error and nothing else. Counting the call sites instead just
    // meant adding a legitimate one broke the test while an unredacted log
    // slipped through unnoticed — the opposite of what this guards.
    // `void _logSessionRestoreFailure(Object error)` is the declaration, not a
    // call site.
    final logCalls = RegExp(
      r'(?<!void )_logSessionRestoreFailure\(([^)]*)\)',
    ).allMatches(service);
    expect(logCalls, isNotEmpty);
    for (final call in logCalls) {
      expect(call.group(1), 'error');
    }
    expect(
      service,
      contains("'Auth0 session restoration failed (\${error.runtimeType}).'"),
    );
    expect(
      service,
      isNot(contains(r'Auth0 session restoration failed: $error')),
    );
  });
}
