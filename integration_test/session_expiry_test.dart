import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/ui/widgets/song_info_bottom_sheet.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// A lapsed session used to be invisible: `tryRestoreSession` returned null,
/// the account row looked exactly like "never signed in", and sync silently
/// stopped reaching the account while edits piled up locally. These drive the
/// real Library banner and Settings account row to prove the state is now
/// actually surfaced, dismissible, cleared by signing back in — and that it
/// never blocks editing the library in the meantime.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A device that was signed in as [subject] but can no longer restore it:
  /// the stored subject is what tells `AuthController.init()` this is an
  /// expired session rather than a first run.
  Future<void> seedLapsedSession(String subject) async {
    final prefs = await Hive.openBox(BoxNames.appPrefs);
    await prefs.put(PrefKeys.cloudAccountSubject, subject);
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openLibrary(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.library_music));
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a lapsed session shows the Library banner and the Settings account error',
    (tester) async {
      // restorableSession stays null: the stored subject is all that is left.
      await bootTestApp(
        tester,
        seedHive: () => seedLapsedSession('auth0|user-1'),
        cloudSyncEnabled: true,
      );

      await openLibrary(tester);
      expect(
        find.textContaining('You have been signed out'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

      await openSettings(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(
        find.textContaining('You have been signed out'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'dismissing the banner hides it but keeps the Settings account error',
    (tester) async {
      await bootTestApp(
        tester,
        seedHive: () => seedLapsedSession('auth0|user-1'),
        cloudSyncEnabled: true,
      );

      await openLibrary(tester);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);

      // The badge is what persists until the session is actually restored.
      await openSettings(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    },
  );

  testWidgets('tapping the banner opens Settings with Account expanded', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await bootTestApp(
      tester,
      authService: auth,
      seedHive: () => seedLapsedSession('auth0|user-1'),
      cloudSyncEnabled: true,
    );

    await openLibrary(tester);
    // The message itself, not the dismiss button beside it.
    await tester.tap(find.textContaining('You have been signed out'));
    await tester.pumpAndSettle();

    // Landed on Settings with the section already open, so the way to fix it
    // is right there rather than behind another tap.
    expect(find.text('Login / Register'), findsOneWidget);

    auth.nextLogin = testUserProfile(sub: 'auth0|user-1');
    await tester.tap(find.text('Login / Register'));
    await pumpFrames(tester);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('signing back in clears the banner and the account error', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await bootTestApp(
      tester,
      authService: auth,
      seedHive: () => seedLapsedSession('auth0|user-1'),
      cloudSyncEnabled: true,
    );

    await openSettings(tester);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    auth.nextLogin = testUserProfile(sub: 'auth0|user-1');
    await tester.tap(find.text('Login / Register'));
    await pumpFrames(tester);

    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.textContaining('You have been signed out'), findsNothing);

    await openLibrary(tester);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets(
    'after signing out, adding an album still works and the banner says '
    'it is not reaching the account',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      final handle = await bootTestApp(
        tester,
        authService: auth,
        cloudSyncEnabled: true,
      );

      // Signed in: nothing to warn about yet.
      await openLibrary(tester);
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);

      // A deliberate sign-out, not a lapsed token. The device keeps its
      // library and still belongs to the account.
      await openSettings(tester);
      await tester.tap(find.text('Logout'));
      await pumpFrames(tester);

      // Add an album to the collection while signed out. Through the
      // repository rather than the album screen: Home renders only Quick
      // Picks until scrolled, so reaching that screen is a scroll-dependent
      // detour, and what is under test here is what a library edit made while
      // signed out looks like afterwards — not the route taken to make it.
      final library = handle.container.read(libraryRepositoryProvider);
      await library.saveAlbum(
        Album(
          title: 'Offline Album',
          browseId: 'offline-album',
          thumbnailUrl: 'https://example.test/album.png',
          artists: const [],
          audioPlaylistId: 'offline-album-playlist',
        ),
      );

      // The edit lands locally — being signed out never makes the library
      // read-only.
      final albums = await library.getAlbums();
      expect(albums.map((album) => album.browseId), contains('offline-album'));

      // And the banner is there to say it is going nowhere until they sign
      // back in, which a plain sign-out used to leave completely unsaid.
      await openLibrary(tester);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.textContaining('You have been signed out'), findsOneWidget);
    },
  );

  testWidgets(
    'a session that dies mid-run surfaces without waiting for a relaunch',
    (tester) async {
      // Windows keeps its own credentials, and a refresh Auth0 rejects used to
      // clear them silently: the account row still showed a signed-in user,
      // sync kept "running", and every cloud call quietly 401'd until the app
      // was next launched. The banner is derived from being signed out, so all
      // that was missing was anyone saying it had happened.
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      await bootTestApp(tester, authService: auth, cloudSyncEnabled: true);
      addTearDown(auth.dispose);

      await openLibrary(tester);
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);

      auth.expireSession();
      await pumpFrames(tester);

      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.textContaining('You have been signed out'), findsOneWidget);

      await openSettings(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Login / Register'), findsOneWidget);
    },
  );

  testWidgets('signing back in after a mid-run expiry clears the warning', (
    tester,
  ) async {
    final auth = FakeAuthService()
      ..restorableSession = testUserProfile(sub: 'auth0|user-1');
    await bootTestApp(tester, authService: auth, cloudSyncEnabled: true);
    addTearDown(auth.dispose);

    auth.expireSession();
    await pumpFrames(tester);

    await openSettings(tester);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    auth.nextLogin = testUserProfile(sub: 'auth0|user-1');
    await tester.tap(find.text('Login / Register'));
    await pumpFrames(tester);

    expect(find.byIcon(Icons.error_outline), findsNothing);
    await openLibrary(tester);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('the library stays editable while the session is lapsed', (
    tester,
  ) async {
    await bootTestApp(
      tester,
      seedHive: () => seedLapsedSession('auth0|user-1'),
      cloudSyncEnabled: true,
    );

    // A stalled sync must never become a read-only library: the edit is made
    // locally now and pushed whenever the account is reachable again.
    await tester.longPress(find.text('Fixture Song'));
    await tester.pumpAndSettle();
    // Scoped to the sheet: the player behind it has its own favourite button.
    await tester.tap(
      find.descendant(
        of: find.byType(SongInfoBottomSheet),
        matching: find.byIcon(Icons.favorite_border),
      ),
    );
    await tester.pumpAndSettle();

    final favourites = await Hive.openBox(BoxNames.libFav);
    expect(favourites.containsKey('song-1'), isTrue);
  });
}
