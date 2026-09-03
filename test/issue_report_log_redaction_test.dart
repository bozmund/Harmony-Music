import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/crash_diagnostics_service.dart';

void main() {
  group('redactDiagnosticLine', () {
    test('a signed media URL loses its query string', () {
      const line =
          'playing https://rr3---sn-x.googlevideo.com/videoplayback'
          '?expire=1&sig=SECRET&ei=abc';

      final redacted = redactDiagnosticLine(line);

      // The whole authorisation for a media URL lives in its query string.
      expect(redacted, isNot(contains('SECRET')));
      expect(redacted, isNot(contains('expire=')));
      // Host and path stay: which CDN served it is diagnostic, and a line that
      // no longer says what it was doing is not worth attaching.
      expect(redacted, contains('googlevideo.com/videoplayback?<redacted>'));
    });

    test('a resolver URL is redacted the same way', () {
      final redacted = redactDiagnosticLine(
        'src=resolver://track/abc?token=xyz',
      );

      expect(redacted, isNot(contains('xyz')));
      expect(redacted, contains('resolver://track/abc?<redacted>'));
    });

    test('a bearer token is masked', () {
      final redacted = redactDiagnosticLine('header Bearer eyJhbGciOi.J9-x_y');

      expect(redacted, 'header Bearer <redacted>');
    });

    test('a Windows home path loses the account name', () {
      final redacted = redactDiagnosticLine(
        r'saved to C:\Users\eboac\AppData\Roaming\harmonymusic',
      );

      expect(redacted, isNot(contains('eboac')));
      // The rest of the path is kept - which directory it was is the point.
      expect(redacted, contains(r'AppData\Roaming\harmonymusic'));
    });

    test('a POSIX home path loses the account name', () {
      expect(
        redactDiagnosticLine('at /home/jan/Music/x.mp3'),
        'at /home/<user>/Music/x.mp3',
      );
      expect(
        redactDiagnosticLine('at /Users/jan/Music/x.mp3'),
        'at /Users/<user>/Music/x.mp3',
      );
    });

    test('song titles and ids survive', () {
      // Deliberately kept: the state dump already publishes both, and a log
      // that cannot be matched to what the reporter was doing is no use.
      const line = 'surface[button] song=eaPzCHEQExs title="Hypnotize"';

      expect(redactDiagnosticLine(line), line);
    });
  });

  group('the report body carries the log', () {
    test('the payload includes a redacted tail', () {
      final dialog = File(
        'lib/ui/widgets/issue_report_dialog.dart',
      ).readAsStringSync();

      expect(
        dialog,
        contains("'recentLog': CrashDiagnosticsService.instance.recentLog()"),
      );
      expect(dialog, contains('**Recent log**'));
    });

    test('the tail is bounded in both lines and characters', () {
      final service = File(
        'lib/services/crash_diagnostics_service.dart',
      ).readAsStringSync();

      // A GitHub issue body is capped, and the buffer holds 240 lines of up to
      // 2000 chars each - far past that limit if handed over whole.
      expect(
        service,
        contains(
          'String recentLog({int maxLines = 120, int maxChars = 12000})',
        ),
      );
      // Newest kept: a failure is at the end of the log, and the breadcrumbs
      // that explain it are just above it.
      expect(service, contains('for (final line in lines.reversed)'));
      expect(service, contains('redactDiagnosticLine(line)'));
    });
  });
}
