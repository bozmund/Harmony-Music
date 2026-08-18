import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'account_lifecycle_smoke_test.dart' as account_lifecycle_smoke;
import 'account_songs_filter_test.dart' as account_songs_filter;
import 'account_switch_test.dart' as account_switch;
import 'app_smoke_test.dart' as app_smoke;
import 'player_behavior_test.dart' as player_behavior;
import 'resolver_phone_test.dart' as resolver_phone;
import 'remote_playback_test.dart' as remote_playback;
import 'session_expiry_test.dart' as session_expiry;
import 'song_resolve_live_test.dart' as song_resolve_live;
import 'unliked_download_dialog_test.dart' as unliked_download_dialog;

/// Runs every integration test from one entrypoint.
///
/// `flutter test integration_test/` treats each file as a separate run: it
/// rebuilds the APK and reinstalls it per file, which costs far more than the
/// tests themselves. Calling each file's `main()` inside a group here means one
/// build and one install for the whole suite:
///
/// ```bash
/// flutter test integration_test/all_tests.dart -d <device>
/// ```
///
/// The individual files stay runnable on their own — that is still the right
/// way to iterate on one scenario, since a single build is only a win when
/// running the whole set.
///
/// One process for everything does mean static state outlives a file: the
/// harness gives each test its own Hive directory and provider container, but
/// genuinely process-wide singletons (`AudioService`'s handler, the controller
/// registries) are shared. That is why the harness registers one audio handler
/// and resets it between boots rather than building a new one per test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('app smoke', app_smoke.main);
  group('player behavior', player_behavior.main);
  group('remote playback', remote_playback.main);
  group('account songs filter', account_songs_filter.main);
  group('unliked download dialog', unliked_download_dialog.main);
  group('account switch', account_switch.main);
  group('session expiry', session_expiry.main);
  group('account lifecycle smoke', account_lifecycle_smoke.main);
  group('resolver phone', resolver_phone.main);
  // Skips itself unless LIVE_RESOLVE_SONG_ID is defined; see the file header.
  group('song resolve live', song_resolve_live.main);
}
