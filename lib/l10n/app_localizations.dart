import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hr'),
  ];

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @add5Minutes.
  ///
  /// In en, this message translates to:
  /// **'Add 5 minutes'**
  String get add5Minutes;

  /// No description provided for @addMultipleSongs.
  ///
  /// In en, this message translates to:
  /// **'Add songs to playlist'**
  String get addMultipleSongs;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// No description provided for @album.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get album;

  /// No description provided for @albumBookmarkAddAlert.
  ///
  /// In en, this message translates to:
  /// **'Album bookmarked!'**
  String get albumBookmarkAddAlert;

  /// No description provided for @albumBookmarkRemoveAlert.
  ///
  /// In en, this message translates to:
  /// **'Album bookmark removed!'**
  String get albumBookmarkRemoveAlert;

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// No description provided for @allFieldsReqMsg.
  ///
  /// In en, this message translates to:
  /// **'All fields required'**
  String get allFieldsReqMsg;

  /// No description provided for @androidBackupWarning.
  ///
  /// In en, this message translates to:
  /// **'Not tested: Selecting the checkbox after downloading more than 60 files, process may consume a large amount of memory and could cause the phone or app to crash. Proceed at your own risk.'**
  String get androidBackupWarning;

  /// No description provided for @appInfo.
  ///
  /// In en, this message translates to:
  /// **'App Info'**
  String get appInfo;

  /// No description provided for @artistBookmarkAddAlert.
  ///
  /// In en, this message translates to:
  /// **'Artist bookmarked!'**
  String get artistBookmarkAddAlert;

  /// No description provided for @artistBookmarkRemoveAlert.
  ///
  /// In en, this message translates to:
  /// **'Artist bookmark removed!'**
  String get artistBookmarkRemoveAlert;

  /// No description provided for @artistDesNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Description not available!'**
  String get artistDesNotAvailable;

  /// No description provided for @artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// No description provided for @audioCodec.
  ///
  /// In en, this message translates to:
  /// **'Audio Codec'**
  String get audioCodec;

  /// No description provided for @autoDownFavSong.
  ///
  /// In en, this message translates to:
  /// **'Auto download favorite songs'**
  String get autoDownFavSong;

  /// No description provided for @autoDownFavSongDes.
  ///
  /// In en, this message translates to:
  /// **'Automatically download favorite songs when added to favorites'**
  String get autoDownFavSongDes;

  /// No description provided for @autoOpenPlayer.
  ///
  /// In en, this message translates to:
  /// **'Auto open player screen'**
  String get autoOpenPlayer;

  /// No description provided for @autoOpenPlayerDes.
  ///
  /// In en, this message translates to:
  /// **'Enable/disable auto opening of player full screen on selection of song for play'**
  String get autoOpenPlayerDes;

  /// No description provided for @backFilesFound.
  ///
  /// In en, this message translates to:
  /// **'databases found'**
  String get backFilesFound;

  /// No description provided for @backgroundPlay.
  ///
  /// In en, this message translates to:
  /// **'Background music play'**
  String get backgroundPlay;

  /// No description provided for @backgroundPlayDes.
  ///
  /// In en, this message translates to:
  /// **'Enable/Disable music playing in background (App can be accessed from system tray when app is running in background)'**
  String get backgroundPlayDes;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @backupAppData.
  ///
  /// In en, this message translates to:
  /// **'Backup App data'**
  String get backupAppData;

  /// No description provided for @backupInProgress.
  ///
  /// In en, this message translates to:
  /// **'Backup in progress...'**
  String get backupInProgress;

  /// No description provided for @backupMsg.
  ///
  /// In en, this message translates to:
  /// **'Backup successfully saved!'**
  String get backupMsg;

  /// No description provided for @backupSettingsAndPlaylistsDes.
  ///
  /// In en, this message translates to:
  /// **'Saves all settings, playlists and login data in a backup file'**
  String get backupSettingsAndPlaylistsDes;

  /// No description provided for @basedOnLast.
  ///
  /// In en, this message translates to:
  /// **'Based on last interaction'**
  String get basedOnLast;

  /// No description provided for @bitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get bitrate;

  /// No description provided for @blacklistPlaylistResetAlert.
  ///
  /// In en, this message translates to:
  /// **'Reset successfully!'**
  String get blacklistPlaylistResetAlert;

  /// No description provided for @by.
  ///
  /// In en, this message translates to:
  /// **'by'**
  String get by;

  /// No description provided for @cacheHomeScreenData.
  ///
  /// In en, this message translates to:
  /// **'Cache home screen content data'**
  String get cacheHomeScreenData;

  /// No description provided for @cacheHomeScreenDataDes.
  ///
  /// In en, this message translates to:
  /// **'Enable Caching home screen content data, Home screen will load instantly if this option is enabled'**
  String get cacheHomeScreenDataDes;

  /// No description provided for @cacheSongs.
  ///
  /// In en, this message translates to:
  /// **'Cache Songs'**
  String get cacheSongs;

  /// No description provided for @cacheSongsDes.
  ///
  /// In en, this message translates to:
  /// **'Caching songs while playing for future/offline playback, it will take additional space on your device'**
  String get cacheSongsDes;

  /// No description provided for @cachedOrOffline.
  ///
  /// In en, this message translates to:
  /// **'Cached/Offline'**
  String get cachedOrOffline;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelTimer.
  ///
  /// In en, this message translates to:
  /// **'Cancel timer'**
  String get cancelTimer;

  /// No description provided for @cancelTimerAlert.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer cancelled'**
  String get cancelTimerAlert;

  /// No description provided for @clearImgCache.
  ///
  /// In en, this message translates to:
  /// **'Clear images cache'**
  String get clearImgCache;

  /// No description provided for @clearImgCacheAlert.
  ///
  /// In en, this message translates to:
  /// **'Images cache cleared successfully'**
  String get clearImgCacheAlert;

  /// No description provided for @clearImgCacheDes.
  ///
  /// In en, this message translates to:
  /// **'Click here to clear cached thumbnails/images. (Not recommended unless want to refresh cached images data)'**
  String get clearImgCacheDes;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @closeApp.
  ///
  /// In en, this message translates to:
  /// **'Close App'**
  String get closeApp;

  /// No description provided for @communityplaylists.
  ///
  /// In en, this message translates to:
  /// **'Community Playlists'**
  String get communityplaylists;

  /// No description provided for @content.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get content;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createNAdd.
  ///
  /// In en, this message translates to:
  /// **'Create & add'**
  String get createNAdd;

  /// No description provided for @customIns.
  ///
  /// In en, this message translates to:
  /// **'Custom Instance'**
  String get customIns;

  /// No description provided for @customInsSelectMsg.
  ///
  /// In en, this message translates to:
  /// **'Please select Custom Instance'**
  String get customInsSelectMsg;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @deleteDownloadData.
  ///
  /// In en, this message translates to:
  /// **'Remove from downloads'**
  String get deleteDownloadData;

  /// No description provided for @deleteDownloadedDataAlert.
  ///
  /// In en, this message translates to:
  /// **'Successfully removed from downloads!'**
  String get deleteDownloadedDataAlert;

  /// No description provided for @disableTransitionAnimation.
  ///
  /// In en, this message translates to:
  /// **'Disable transition animation'**
  String get disableTransitionAnimation;

  /// No description provided for @disableTransitionAnimationDes.
  ///
  /// In en, this message translates to:
  /// **'Enable this option to disable tab transition animation'**
  String get disableTransitionAnimationDes;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discover;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @dontShowInfoAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show this info again'**
  String get dontShowInfoAgain;

  /// No description provided for @downFilesFound.
  ///
  /// In en, this message translates to:
  /// **'downloaded files found'**
  String get downFilesFound;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @downloadError2.
  ///
  /// In en, this message translates to:
  /// **'Requested song is not downloadable due to server restriction. You may try again'**
  String get downloadError2;

  /// No description provided for @downloadError3.
  ///
  /// In en, this message translates to:
  /// **'Downloading failed due to network/stream error! Please try again'**
  String get downloadError3;

  /// No description provided for @downloadLocation.
  ///
  /// In en, this message translates to:
  /// **'Download Location'**
  String get downloadLocation;

  /// No description provided for @downloadingFormat.
  ///
  /// In en, this message translates to:
  /// **'Downloading File Format'**
  String get downloadingFormat;

  /// No description provided for @downloadingFormatDes.
  ///
  /// In en, this message translates to:
  /// **'Select downloading file format. \"Opus\" will provide best quality'**
  String get downloadingFormatDes;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @emptyPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Empty playlist!'**
  String get emptyPlaylist;

  /// No description provided for @enableBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Bottom navigation bar'**
  String get enableBottomNav;

  /// No description provided for @enableBottomNavDes.
  ///
  /// In en, this message translates to:
  /// **'Switch to bottom navigation bar'**
  String get enableBottomNavDes;

  /// No description provided for @enableSlidableAction.
  ///
  /// In en, this message translates to:
  /// **'Enable slidable actions'**
  String get enableSlidableAction;

  /// No description provided for @enableSlidableActionDes.
  ///
  /// In en, this message translates to:
  /// **'Enable slidable actions on song tile'**
  String get enableSlidableActionDes;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @endOfThisSong.
  ///
  /// In en, this message translates to:
  /// **'End of this song'**
  String get endOfThisSong;

  /// No description provided for @enqueueAll.
  ///
  /// In en, this message translates to:
  /// **'Enqueue all'**
  String get enqueueAll;

  /// No description provided for @enqueueSong.
  ///
  /// In en, this message translates to:
  /// **'Enqueue this song'**
  String get enqueueSong;

  /// No description provided for @equalizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get equalizer;

  /// No description provided for @equalizerDes.
  ///
  /// In en, this message translates to:
  /// **'Open system equalizer'**
  String get equalizerDes;

  /// No description provided for @errorOccurredAlert.
  ///
  /// In en, this message translates to:
  /// **'Some error occured!'**
  String get errorOccurredAlert;

  /// No description provided for @exportDownloadedFiles.
  ///
  /// In en, this message translates to:
  /// **'Export downloaded files'**
  String get exportDownloadedFiles;

  /// No description provided for @exportDownloadedFilesDes.
  ///
  /// In en, this message translates to:
  /// **'Click here to export downloaded file from inApp dir to external dir'**
  String get exportDownloadedFilesDes;

  /// No description provided for @exportError.
  ///
  /// In en, this message translates to:
  /// **'Error exporting playlist'**
  String get exportError;

  /// No description provided for @exportErrorFormat.
  ///
  /// In en, this message translates to:
  /// **'Error formatting playlist data'**
  String get exportErrorFormat;

  /// No description provided for @exportErrorPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission denied while exporting'**
  String get exportErrorPermission;

  /// No description provided for @exportErrorStorage.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage space'**
  String get exportErrorStorage;

  /// No description provided for @exportMsg.
  ///
  /// In en, this message translates to:
  /// **'Files successfully exported'**
  String get exportMsg;

  /// No description provided for @exportPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Export Playlist'**
  String get exportPlaylist;

  /// No description provided for @exportPlaylistCsv.
  ///
  /// In en, this message translates to:
  /// **'Export Playlist as CSV'**
  String get exportPlaylistCsv;

  /// No description provided for @exportPlaylistCsvSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t be imported here'**
  String get exportPlaylistCsvSubtitle;

  /// No description provided for @exportPlaylistJson.
  ///
  /// In en, this message translates to:
  /// **'Export playlist to JSON'**
  String get exportPlaylistJson;

  /// No description provided for @exportPlaylistJsonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This format can be imported'**
  String get exportPlaylistJsonSubtitle;

  /// No description provided for @exportToYouTubeMusic.
  ///
  /// In en, this message translates to:
  /// **'Export to Youtube music'**
  String get exportToYouTubeMusic;

  /// No description provided for @exportToYouTubeMusicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'It will push your playlist (songs < 50) to current queue, don\'t forget to add to playlist/save after opening in YtMusic'**
  String get exportToYouTubeMusicSubtitle;

  /// No description provided for @exportedFileLocation.
  ///
  /// In en, this message translates to:
  /// **'Downloaded file export location'**
  String get exportedFileLocation;

  /// No description provided for @exporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting...'**
  String get exporting;

  /// No description provided for @exportingPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Exporting playlist...'**
  String get exportingPlaylist;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @featuredplaylists.
  ///
  /// In en, this message translates to:
  /// **'Featured Playlists'**
  String get featuredplaylists;

  /// No description provided for @fileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get fileNotFound;

  /// No description provided for @firstLibraryTab.
  ///
  /// In en, this message translates to:
  /// **'First library tab'**
  String get firstLibraryTab;

  /// No description provided for @firstLibraryTabDes.
  ///
  /// In en, this message translates to:
  /// **'Select which tab to show first in Library'**
  String get firstLibraryTabDes;

  /// No description provided for @for1.
  ///
  /// In en, this message translates to:
  /// **'for'**
  String get for1;

  /// No description provided for @gesture.
  ///
  /// In en, this message translates to:
  /// **'Gesture'**
  String get gesture;

  /// No description provided for @github.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get github;

  /// No description provided for @githubDes.
  ///
  /// In en, this message translates to:
  /// **'View GitHub source code \nif you like this project, don\'t forget to give a ⭐'**
  String get githubDes;

  /// No description provided for @goToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Go to album'**
  String get goToAlbum;

  /// No description provided for @goToDownloadPage.
  ///
  /// In en, this message translates to:
  /// **'Click here to go to download page'**
  String get goToDownloadPage;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @hintApiUrl.
  ///
  /// In en, this message translates to:
  /// **'API URL to Piped instance'**
  String get hintApiUrl;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @homeContentCount.
  ///
  /// In en, this message translates to:
  /// **'Home content count'**
  String get homeContentCount;

  /// No description provided for @homeContentCountDes.
  ///
  /// In en, this message translates to:
  /// **'Select the number of initial homescreen-content(approx). Lesser results faster loading'**
  String get homeContentCountDes;

  /// No description provided for @id.
  ///
  /// In en, this message translates to:
  /// **'Id'**
  String get id;

  /// No description provided for @ignoreBatOpt.
  ///
  /// In en, this message translates to:
  /// **'Ignore battery optimization'**
  String get ignoreBatOpt;

  /// No description provided for @ignoreBatOptDes.
  ///
  /// In en, this message translates to:
  /// **'If you are facing notification issues or playback stopped by system optimization, please enable this option'**
  String get ignoreBatOptDes;

  /// No description provided for @importError.
  ///
  /// In en, this message translates to:
  /// **'Error importing playlist'**
  String get importError;

  /// No description provided for @importErrorDatabase.
  ///
  /// In en, this message translates to:
  /// **'Error saving to database'**
  String get importErrorDatabase;

  /// No description provided for @importErrorFileAccess.
  ///
  /// In en, this message translates to:
  /// **'Could not access the selected file'**
  String get importErrorFileAccess;

  /// No description provided for @importErrorFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid file format'**
  String get importErrorFormat;

  /// No description provided for @importLargeFileNote.
  ///
  /// In en, this message translates to:
  /// **'Note: Large playlists may take longer to import'**
  String get importLargeFileNote;

  /// No description provided for @importPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Import Playlist'**
  String get importPlaylist;

  /// No description provided for @importPlaylistDesc.
  ///
  /// In en, this message translates to:
  /// **'Select a previously exported playlist JSON file to import'**
  String get importPlaylistDesc;

  /// No description provided for @importingPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Importing playlist...'**
  String get importingPlaylist;

  /// No description provided for @includeDownloadedFiles.
  ///
  /// In en, this message translates to:
  /// **'Include downloded songs files'**
  String get includeDownloadedFiles;

  /// No description provided for @invalidPlaylistFile.
  ///
  /// In en, this message translates to:
  /// **'Invalid playlist file structure'**
  String get invalidPlaylistFile;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'items'**
  String get items;

  /// No description provided for @keepScreenOnWhilePlaying.
  ///
  /// In en, this message translates to:
  /// **'Keep screen on while playing'**
  String get keepScreenOnWhilePlaying;

  /// No description provided for @keepScreenOnWhilePlayingDes.
  ///
  /// In en, this message translates to:
  /// **'If enabled, the device screen will stay awake while music is playing'**
  String get keepScreenOnWhilePlayingDes;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageDes.
  ///
  /// In en, this message translates to:
  /// **'Set App language'**
  String get languageDes;

  /// No description provided for @letsStart.
  ///
  /// In en, this message translates to:
  /// **'Let\'s start..'**
  String get letsStart;

  /// No description provided for @libAlbums.
  ///
  /// In en, this message translates to:
  /// **'Library Albums'**
  String get libAlbums;

  /// No description provided for @libArtists.
  ///
  /// In en, this message translates to:
  /// **'Library Artists'**
  String get libArtists;

  /// No description provided for @libPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Library Playlists'**
  String get libPlaylists;

  /// No description provided for @libSongs.
  ///
  /// In en, this message translates to:
  /// **'Library Songs'**
  String get libSongs;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @link.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// No description provided for @linkAlert.
  ///
  /// In en, this message translates to:
  /// **'Linked successfully!'**
  String get linkAlert;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopied;

  /// No description provided for @linkPipedDes.
  ///
  /// In en, this message translates to:
  /// **'Link with piped for playlists'**
  String get linkPipedDes;

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @loudnessDb.
  ///
  /// In en, this message translates to:
  /// **'LoudnessDb'**
  String get loudnessDb;

  /// No description provided for @loudnessNormalization.
  ///
  /// In en, this message translates to:
  /// **'Loudness normalization'**
  String get loudnessNormalization;

  /// No description provided for @loudnessNormalizationDes.
  ///
  /// In en, this message translates to:
  /// **'Sets same lavel of loudness for all songs (Experimental) (Will not work on songs downloaded on previous version(< v1.10.0))'**
  String get loudnessNormalizationDes;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @lyricsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Lyrics not available!'**
  String get lyricsNotAvailable;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get minutes;

  /// No description provided for @misc.
  ///
  /// In en, this message translates to:
  /// **'Misc'**
  String get misc;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error! Check your network connection.'**
  String get networkError;

  /// No description provided for @networkError1.
  ///
  /// In en, this message translates to:
  /// **'Oops network error!'**
  String get networkError1;

  /// No description provided for @newVersionAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version available!'**
  String get newVersionAvailable;

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks!'**
  String get noBookmarks;

  /// No description provided for @noLibPlaylist.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any lib playlist!'**
  String get noLibPlaylist;

  /// No description provided for @noOfflineSong.
  ///
  /// In en, this message translates to:
  /// **'No offline songs!'**
  String get noOfflineSong;

  /// No description provided for @noSavedSearches.
  ///
  /// In en, this message translates to:
  /// **'No saved searches'**
  String get noSavedSearches;

  /// No description provided for @nomatch.
  ///
  /// In en, this message translates to:
  /// **'No Match found for'**
  String get nomatch;

  /// No description provided for @notaSongVideo.
  ///
  /// In en, this message translates to:
  /// **'Not a Song/Music-Video!'**
  String get notaSongVideo;

  /// No description provided for @notaValidLink.
  ///
  /// In en, this message translates to:
  /// **'Not a valid link!'**
  String get notaValidLink;

  /// No description provided for @openIn.
  ///
  /// In en, this message translates to:
  /// **'Open in'**
  String get openIn;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get operationFailed;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @personalisation.
  ///
  /// In en, this message translates to:
  /// **'Personalisation'**
  String get personalisation;

  /// No description provided for @pipedPlaylistSyncAlert.
  ///
  /// In en, this message translates to:
  /// **'Piped playlist synced!'**
  String get pipedPlaylistSyncAlert;

  /// No description provided for @plain.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get plain;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get playNext;

  /// No description provided for @playNextMsg.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get playNextMsg;

  /// No description provided for @playerUi.
  ///
  /// In en, this message translates to:
  /// **'Player Ui'**
  String get playerUi;

  /// No description provided for @playerUiDes.
  ///
  /// In en, this message translates to:
  /// **'Select player user interface'**
  String get playerUiDes;

  /// No description provided for @playingFromAlbum.
  ///
  /// In en, this message translates to:
  /// **'PLAYING FROM ALBUM'**
  String get playingFromAlbum;

  /// No description provided for @playingFromArtist.
  ///
  /// In en, this message translates to:
  /// **'PLAYING FROM ARTIST'**
  String get playingFromArtist;

  /// No description provided for @playingFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'PLAYING FROM PLAYLIST'**
  String get playingFromPlaylist;

  /// No description provided for @playingFromSelection.
  ///
  /// In en, this message translates to:
  /// **'PLAYING FROM SELECTION'**
  String get playingFromSelection;

  /// No description provided for @playlistBlacklistAlert.
  ///
  /// In en, this message translates to:
  /// **'Playlist blacklisted!'**
  String get playlistBlacklistAlert;

  /// No description provided for @playlistBookmarkAddAlert.
  ///
  /// In en, this message translates to:
  /// **'Playlist bookmarked!'**
  String get playlistBookmarkAddAlert;

  /// No description provided for @playlistBookmarkRemoveAlert.
  ///
  /// In en, this message translates to:
  /// **'Playlist bookmark removed!'**
  String get playlistBookmarkRemoveAlert;

  /// No description provided for @playlistCreatedAlert.
  ///
  /// In en, this message translates to:
  /// **'Playlist created!'**
  String get playlistCreatedAlert;

  /// No description provided for @playlistCreatedNSongAddedAlert.
  ///
  /// In en, this message translates to:
  /// **'Playlist created & song added!'**
  String get playlistCreatedNSongAddedAlert;

  /// No description provided for @playlistExportedMsg.
  ///
  /// In en, this message translates to:
  /// **'Playlist exported successfully to'**
  String get playlistExportedMsg;

  /// No description provided for @playlistImportedMsg.
  ///
  /// In en, this message translates to:
  /// **'Playlist imported successfully'**
  String get playlistImportedMsg;

  /// No description provided for @playlistRemovedAlert.
  ///
  /// In en, this message translates to:
  /// **'Playlist removed!'**
  String get playlistRemovedAlert;

  /// No description provided for @playlistRenameAlert.
  ///
  /// In en, this message translates to:
  /// **'Renamed successfully!'**
  String get playlistRenameAlert;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @processFiles.
  ///
  /// In en, this message translates to:
  /// **'Processing files...'**
  String get processFiles;

  /// No description provided for @queueLoop.
  ///
  /// In en, this message translates to:
  /// **'Queue loop'**
  String get queueLoop;

  /// No description provided for @queueLoopNotDisMsg1.
  ///
  /// In en, this message translates to:
  /// **'Queue loop mode cannot be disabled when shuffle mode is enabled.'**
  String get queueLoopNotDisMsg1;

  /// No description provided for @queueLoopNotDisMsg2.
  ///
  /// In en, this message translates to:
  /// **'Queue loop mode cannot be enabled in radio mode.'**
  String get queueLoopNotDisMsg2;

  /// No description provided for @queueRearrangingDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Queue can\'t be rearranged when shuffle mode is enabled'**
  String get queueRearrangingDeniedMessage;

  /// No description provided for @queueShufflingDeniedMsg.
  ///
  /// In en, this message translates to:
  /// **'Queue can\'t be shuffled when shuffle mode is enabled'**
  String get queueShufflingDeniedMsg;

  /// No description provided for @quickpicks.
  ///
  /// In en, this message translates to:
  /// **'Quick Picks'**
  String get quickpicks;

  /// No description provided for @radioNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Radio not available for this artist!'**
  String get radioNotAvailable;

  /// No description provided for @randomRadio.
  ///
  /// In en, this message translates to:
  /// **'Random Radio'**
  String get randomRadio;

  /// No description provided for @randomSelection.
  ///
  /// In en, this message translates to:
  /// **'Random Selection'**
  String get randomSelection;

  /// No description provided for @reArrangePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Rearrange playlist'**
  String get reArrangePlaylist;

  /// No description provided for @reArrangeSongs.
  ///
  /// In en, this message translates to:
  /// **'Rearrange songs'**
  String get reArrangeSongs;

  /// No description provided for @recentlyPlayed.
  ///
  /// In en, this message translates to:
  /// **'Recently Played'**
  String get recentlyPlayed;

  /// No description provided for @removeFromLib.
  ///
  /// In en, this message translates to:
  /// **'Remove from Library Songs'**
  String get removeFromLib;

  /// No description provided for @removeFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get removeFromPlaylist;

  /// No description provided for @removeFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get removeFromQueue;

  /// No description provided for @removeMultiple.
  ///
  /// In en, this message translates to:
  /// **'Remove multiple songs'**
  String get removeMultiple;

  /// No description provided for @removePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove playlist'**
  String get removePlaylist;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renamePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Rename Playlist'**
  String get renamePlaylist;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @resetBlacklistedPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Reset blacklisted playlists'**
  String get resetBlacklistedPlaylist;

  /// No description provided for @resetBlacklistedPlaylistDes.
  ///
  /// In en, this message translates to:
  /// **'Reset all the piped blacklisted playlists'**
  String get resetBlacklistedPlaylistDes;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore default settings'**
  String get resetToDefault;

  /// No description provided for @resetToDefaultDes.
  ///
  /// In en, this message translates to:
  /// **'Reset app settings to default (Restart required)'**
  String get resetToDefaultDes;

  /// No description provided for @resetToDefaultMsg.
  ///
  /// In en, this message translates to:
  /// **'Settings reset to default completed, Please restart app'**
  String get resetToDefaultMsg;

  /// No description provided for @restartApp.
  ///
  /// In en, this message translates to:
  /// **'Restart App'**
  String get restartApp;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @restoreAppData.
  ///
  /// In en, this message translates to:
  /// **'Restore App data'**
  String get restoreAppData;

  /// No description provided for @restoreLastPlaybackSession.
  ///
  /// In en, this message translates to:
  /// **'Restore last playback session'**
  String get restoreLastPlaybackSession;

  /// No description provided for @restoreLastPlaybackSessionDes.
  ///
  /// In en, this message translates to:
  /// **'Automatically restore the last playback session on app start'**
  String get restoreLastPlaybackSessionDes;

  /// No description provided for @restoreMsg.
  ///
  /// In en, this message translates to:
  /// **'Successfully restored!\nChanges are applied on restart'**
  String get restoreMsg;

  /// No description provided for @restoreSettingsAndPlaylistsDes.
  ///
  /// In en, this message translates to:
  /// **'Restores all settings, login data and playlists from a backup file. Overwrites all current data'**
  String get restoreSettingsAndPlaylistsDes;

  /// No description provided for @restoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring...'**
  String get restoring;

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get results;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry!'**
  String get retry;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning...'**
  String get scanning;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchDes.
  ///
  /// In en, this message translates to:
  /// **'Songs, Playlist, Album or Artist'**
  String get searchDes;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search; use comma, !, a:, or t:'**
  String get searchHint;

  /// No description provided for @searchRes.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchRes;

  /// No description provided for @searchSaved.
  ///
  /// In en, this message translates to:
  /// **'Search saved'**
  String get searchSaved;

  /// No description provided for @searches.
  ///
  /// In en, this message translates to:
  /// **'Searches'**
  String get searches;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @selectAuthIns.
  ///
  /// In en, this message translates to:
  /// **'Select Auth Instance'**
  String get selectAuthIns;

  /// No description provided for @selectAuthInsMsg.
  ///
  /// In en, this message translates to:
  /// **'Please select Authentication instance!'**
  String get selectAuthInsMsg;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get selectFile;

  /// No description provided for @selectSongs.
  ///
  /// In en, this message translates to:
  /// **'Select songs'**
  String get selectSongs;

  /// No description provided for @setDiscoverContent.
  ///
  /// In en, this message translates to:
  /// **'Set discover content'**
  String get setDiscoverContent;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @shareSong.
  ///
  /// In en, this message translates to:
  /// **'Share this song'**
  String get shareSong;

  /// No description provided for @shuffleQueue.
  ///
  /// In en, this message translates to:
  /// **'Shuffle Queue'**
  String get shuffleQueue;

  /// No description provided for @singles.
  ///
  /// In en, this message translates to:
  /// **'Singles'**
  String get singles;

  /// No description provided for @skipSilence.
  ///
  /// In en, this message translates to:
  /// **'Skip silence'**
  String get skipSilence;

  /// No description provided for @skipSilenceDes.
  ///
  /// In en, this message translates to:
  /// **'Silence will be skipped in music playback'**
  String get skipSilenceDes;

  /// No description provided for @sleepTimeSetAlert.
  ///
  /// In en, this message translates to:
  /// **'Your sleep timer is set'**
  String get sleepTimeSetAlert;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep Timer'**
  String get sleepTimer;

  /// No description provided for @songAddedToPlaylistAlert.
  ///
  /// In en, this message translates to:
  /// **'Song added to playlist!'**
  String get songAddedToPlaylistAlert;

  /// No description provided for @songAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Song already exists!'**
  String get songAlreadyExists;

  /// No description provided for @songAlreadyOfflineAlert.
  ///
  /// In en, this message translates to:
  /// **'Song already offline in cache'**
  String get songAlreadyOfflineAlert;

  /// No description provided for @songEnqueueAlert.
  ///
  /// In en, this message translates to:
  /// **'Song enqueued!'**
  String get songEnqueueAlert;

  /// No description provided for @songInfo.
  ///
  /// In en, this message translates to:
  /// **'Song Info'**
  String get songInfo;

  /// No description provided for @songNotPlayable.
  ///
  /// In en, this message translates to:
  /// **'Song is not playable due to server restriction!'**
  String get songNotPlayable;

  /// No description provided for @songRemovedAlert.
  ///
  /// In en, this message translates to:
  /// **'Removed from'**
  String get songRemovedAlert;

  /// No description provided for @songRemovedFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Removed from queue!'**
  String get songRemovedFromQueue;

  /// No description provided for @songRemovedFromQueueCurrSong.
  ///
  /// In en, this message translates to:
  /// **'You can\'t remove currently playing song'**
  String get songRemovedFromQueueCurrSong;

  /// No description provided for @songs.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get songs;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @startRadio.
  ///
  /// In en, this message translates to:
  /// **'Start radio'**
  String get startRadio;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @stopMusicOnTaskClear.
  ///
  /// In en, this message translates to:
  /// **'Stop music on task clear'**
  String get stopMusicOnTaskClear;

  /// No description provided for @stopMusicOnTaskClearDes.
  ///
  /// In en, this message translates to:
  /// **'Music playback will stop when App being swiped away from the task manager'**
  String get stopMusicOnTaskClearDes;

  /// No description provided for @streamingQuality.
  ///
  /// In en, this message translates to:
  /// **'Streaming quality'**
  String get streamingQuality;

  /// No description provided for @streamingQualityDes.
  ///
  /// In en, this message translates to:
  /// **'Quality of music stream'**
  String get streamingQualityDes;

  /// No description provided for @subscribers.
  ///
  /// In en, this message translates to:
  /// **'subscribers'**
  String get subscribers;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get synced;

  /// No description provided for @syncedLyricsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Synced lyrics not available!'**
  String get syncedLyricsNotAvailable;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @topmusicvideos.
  ///
  /// In en, this message translates to:
  /// **'Top Music Videos'**
  String get topmusicvideos;

  /// No description provided for @trending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get trending;

  /// No description provided for @unLink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get unLink;

  /// No description provided for @unlinkAlert.
  ///
  /// In en, this message translates to:
  /// **'Unlinked successfully!'**
  String get unlinkAlert;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up Next'**
  String get upNext;

  /// No description provided for @urlSearchDes.
  ///
  /// In en, this message translates to:
  /// **'Url detected click on it to open/play associated content'**
  String get urlSearchDes;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @viewArtist.
  ///
  /// In en, this message translates to:
  /// **'View Artist'**
  String get viewArtist;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Harmony Music'**
  String get appTitle;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @optionalAccount.
  ///
  /// In en, this message translates to:
  /// **'Optional Harmony account'**
  String get optionalAccount;

  /// No description provided for @optionalAccountDes.
  ///
  /// In en, this message translates to:
  /// **'Sign in or register through Auth0. Music and library features work without an account.'**
  String get optionalAccountDes;

  /// No description provided for @authNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Auth0 is not configured for this build.'**
  String get authNotConfigured;

  /// No description provided for @authUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Account login is not supported on this platform.'**
  String get authUnsupportedPlatform;

  /// No description provided for @loggedInAs.
  ///
  /// In en, this message translates to:
  /// **'Logged in as'**
  String get loggedInAs;

  /// No description provided for @loginOrRegister.
  ///
  /// In en, this message translates to:
  /// **'Login / Register'**
  String get loginOrRegister;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @createNewPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Create new playlist'**
  String get createNewPlaylist;

  /// No description provided for @musicAndPlayback.
  ///
  /// In en, this message translates to:
  /// **'Music & Playback'**
  String get musicAndPlayback;

  /// No description provided for @dynamicTheme.
  ///
  /// In en, this message translates to:
  /// **'Dynamic'**
  String get dynamicTheme;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @piped.
  ///
  /// In en, this message translates to:
  /// **'Piped'**
  String get piped;

  /// No description provided for @checkUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkUpdate;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'App is up to date'**
  String get upToDate;

  /// No description provided for @checkingUpdate.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates...'**
  String get checkingUpdate;

  /// No description provided for @chooseUpdateChannel.
  ///
  /// In en, this message translates to:
  /// **'Choose your update channel'**
  String get chooseUpdateChannel;

  /// No description provided for @chooseUpdateChannelDes.
  ///
  /// In en, this message translates to:
  /// **'Harmony Music now offers two update channels. Pick how you want to receive updates — you can change this anytime in Settings.'**
  String get chooseUpdateChannelDes;

  /// No description provided for @stableChannelOption.
  ///
  /// In en, this message translates to:
  /// **'Stable (recommended)'**
  String get stableChannelOption;

  /// No description provided for @stableChannelOptionDes.
  ///
  /// In en, this message translates to:
  /// **'Tested, versioned releases. Fewer updates, more reliable.'**
  String get stableChannelOptionDes;

  /// No description provided for @rollingChannelOption.
  ///
  /// In en, this message translates to:
  /// **'Rolling'**
  String get rollingChannelOption;

  /// No description provided for @rollingChannelOptionDes.
  ///
  /// In en, this message translates to:
  /// **'Every new build from development. Newest features first, but may be less stable.'**
  String get rollingChannelOptionDes;

  /// No description provided for @tapToRemoveFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Added — tap to remove'**
  String get tapToRemoveFromPlaylist;

  /// No description provided for @songRemovedFromPlaylistAlert.
  ///
  /// In en, this message translates to:
  /// **'Removed from playlist'**
  String get songRemovedFromPlaylistAlert;

  /// No description provided for @listenTogether.
  ///
  /// In en, this message translates to:
  /// **'Listen together'**
  String get listenTogether;

  /// No description provided for @listenTogetherDes.
  ///
  /// In en, this message translates to:
  /// **'Play in sync with nearby phones'**
  String get listenTogetherDes;

  /// No description provided for @hostSession.
  ///
  /// In en, this message translates to:
  /// **'Host a session'**
  String get hostSession;

  /// No description provided for @hostSessionDes.
  ///
  /// In en, this message translates to:
  /// **'Others join and listen with you'**
  String get hostSessionDes;

  /// No description provided for @joinSession.
  ///
  /// In en, this message translates to:
  /// **'Join a session'**
  String get joinSession;

  /// No description provided for @leaveSession.
  ///
  /// In en, this message translates to:
  /// **'Leave session'**
  String get leaveSession;

  /// No description provided for @endSession.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get endSession;

  /// No description provided for @searchingForSessions.
  ///
  /// In en, this message translates to:
  /// **'Searching for nearby sessions…'**
  String get searchingForSessions;

  /// No description provided for @noSessionsFound.
  ///
  /// In en, this message translates to:
  /// **'No sessions found yet'**
  String get noSessionsFound;

  /// No description provided for @connectVia.
  ///
  /// In en, this message translates to:
  /// **'Connect via'**
  String get connectVia;

  /// No description provided for @wifiTransport.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get wifiTransport;

  /// No description provided for @bluetoothTransport.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get bluetoothTransport;

  /// No description provided for @bothTransports.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth + Wi-Fi'**
  String get bothTransports;

  /// No description provided for @bluetoothDisabled.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bluetooth to use this connection mode.'**
  String get bluetoothDisabled;

  /// No description provided for @wifiDisabled.
  ///
  /// In en, this message translates to:
  /// **'Turn on Wi-Fi to use this connection mode. You do not need to connect to the internet.'**
  String get wifiDisabled;

  /// No description provided for @playServicesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Current Google Play services are required for Bluetooth discovery.'**
  String get playServicesUnavailable;

  /// No description provided for @transportReady.
  ///
  /// In en, this message translates to:
  /// **'Selected connection mode is ready.'**
  String get transportReady;

  /// No description provided for @transportStartupFailed.
  ///
  /// In en, this message translates to:
  /// **'The selected connection mode could not be started.'**
  String get transportStartupFailed;

  /// No description provided for @grantPermissions.
  ///
  /// In en, this message translates to:
  /// **'Grant permissions'**
  String get grantPermissions;

  /// No description provided for @hostingSession.
  ///
  /// In en, this message translates to:
  /// **'Hosting — others can join'**
  String get hostingSession;

  /// No description provided for @connectedToSession.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectedToSession;

  /// No description provided for @connectingToSession.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connectingToSession;

  /// No description provided for @participants.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get participants;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @listenTogetherUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Listen together isn\'t available on this device'**
  String get listenTogetherUnavailable;

  /// No description provided for @confirmConnection.
  ///
  /// In en, this message translates to:
  /// **'Confirm connection'**
  String get confirmConnection;

  /// No description provided for @listenTogetherDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get listenTogetherDeviceName;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @nearbyPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth and Nearby devices permissions are required. Open Android settings and allow them.'**
  String get nearbyPermissionRequired;

  /// No description provided for @nearbyWithWifiFallback.
  ///
  /// In en, this message translates to:
  /// **'Nearby + Wi-Fi fallback'**
  String get nearbyWithWifiFallback;

  /// No description provided for @partyMode.
  ///
  /// In en, this message translates to:
  /// **'Party mode'**
  String get partyMode;

  /// No description provided for @partyModeDes.
  ///
  /// In en, this message translates to:
  /// **'Only the host plays audio; guests control the shared queue.'**
  String get partyModeDes;

  /// No description provided for @partyModeGuestHint.
  ///
  /// In en, this message translates to:
  /// **'Party mode is active: this phone is a remote and will not play audio.'**
  String get partyModeGuestHint;

  /// No description provided for @addedToSharedQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to the shared queue'**
  String get addedToSharedQueue;

  /// No description provided for @notAvailableInSession.
  ///
  /// In en, this message translates to:
  /// **'This action is not available in the current session'**
  String get notAvailableInSession;

  /// No description provided for @listenTogetherGuestAdded.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" added {title}'**
  String listenTogetherGuestAdded(String name, String title);

  /// No description provided for @songsAddedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String songsAddedCount(int count);

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @addToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get addToLibrary;

  /// No description provided for @removeFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Remove from library'**
  String get removeFromLibrary;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @enqueueAlbumSongs.
  ///
  /// In en, this message translates to:
  /// **'Add album songs to queue'**
  String get enqueueAlbumSongs;

  /// No description provided for @downloadAlbumSongs.
  ///
  /// In en, this message translates to:
  /// **'Download album songs'**
  String get downloadAlbumSongs;

  /// No description provided for @shareAlbum.
  ///
  /// In en, this message translates to:
  /// **'Share album'**
  String get shareAlbum;

  /// No description provided for @enqueueSongs.
  ///
  /// In en, this message translates to:
  /// **'Add songs to queue'**
  String get enqueueSongs;

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @downloadPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Download playlist'**
  String get downloadPlaylist;

  /// No description provided for @syncPlaylistSongs.
  ///
  /// In en, this message translates to:
  /// **'Sync playlist songs'**
  String get syncPlaylistSongs;

  /// No description provided for @sharePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Share playlist'**
  String get sharePlaylist;

  /// No description provided for @playlist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlist;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Sort by name'**
  String get sortByName;

  /// No description provided for @sortByDate.
  ///
  /// In en, this message translates to:
  /// **'Sort by date'**
  String get sortByDate;

  /// No description provided for @sortByDuration.
  ///
  /// In en, this message translates to:
  /// **'Sort by duration'**
  String get sortByDuration;

  /// No description provided for @sortAscendNDescend.
  ///
  /// In en, this message translates to:
  /// **'Sort ascending or descending'**
  String get sortAscendNDescend;

  /// No description provided for @listBookmarkRemoveAlert.
  ///
  /// In en, this message translates to:
  /// **'Removed from library'**
  String get listBookmarkRemoveAlert;

  /// No description provided for @blacklistPipedPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Blacklist Piped playlist'**
  String get blacklistPipedPlaylist;

  /// No description provided for @noItems.
  ///
  /// In en, this message translates to:
  /// **'No {title}!'**
  String noItems(String title);

  /// No description provided for @imported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get imported;

  /// No description provided for @importedPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Imported playlist'**
  String get importedPlaylist;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get permissionDenied;

  /// No description provided for @likedNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Liked not downloaded'**
  String get likedNotDownloaded;

  /// No description provided for @importConflicts.
  ///
  /// In en, this message translates to:
  /// **'Import conflicts'**
  String get importConflicts;

  /// No description provided for @importNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'Import needs review'**
  String get importNeedsReview;

  /// No description provided for @resolverBackend.
  ///
  /// In en, this message translates to:
  /// **'Harmony Resolver'**
  String get resolverBackend;

  /// No description provided for @resolverBackendDescription.
  ///
  /// In en, this message translates to:
  /// **'Use the configured Resolver server as an additional playback source.'**
  String get resolverBackendDescription;

  /// No description provided for @resolverPlaybackSource.
  ///
  /// In en, this message translates to:
  /// **'Online playback source'**
  String get resolverPlaybackSource;

  /// No description provided for @resolverPlaybackSourceDescription.
  ///
  /// In en, this message translates to:
  /// **'Debug only: choose which backend provides online audio.'**
  String get resolverPlaybackSourceDescription;

  /// No description provided for @resolverPlaybackSourceBoth.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get resolverPlaybackSourceBoth;

  /// No description provided for @resolverPlaybackSourceResolverOnly.
  ///
  /// In en, this message translates to:
  /// **'Resolver only'**
  String get resolverPlaybackSourceResolverOnly;

  /// No description provided for @resolverPlaybackSourceExistingOnly.
  ///
  /// In en, this message translates to:
  /// **'Existing source only'**
  String get resolverPlaybackSourceExistingOnly;

  /// No description provided for @resolverTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get resolverTestConnection;

  /// No description provided for @resolverDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover on LAN'**
  String get resolverDiscover;

  /// No description provided for @resolverReady.
  ///
  /// In en, this message translates to:
  /// **'Resolver is ready.'**
  String get resolverReady;

  /// No description provided for @resolverUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Resolver could not be reached. Check the address, Wi-Fi, and firewall.'**
  String get resolverUnavailable;

  /// No description provided for @resolverNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Resolver address is not configured.'**
  String get resolverNotConfigured;

  /// No description provided for @resolverAddress.
  ///
  /// In en, this message translates to:
  /// **'Resolver address'**
  String get resolverAddress;

  /// No description provided for @resolverSaveAddress.
  ///
  /// In en, this message translates to:
  /// **'Save address'**
  String get resolverSaveAddress;

  /// No description provided for @resolverResetAddress.
  ///
  /// In en, this message translates to:
  /// **'Reset address'**
  String get resolverResetAddress;

  /// No description provided for @resolverEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get resolverEnvironment;

  /// No description provided for @resolverPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'This song could not be loaded from either playback source. Check your connection and try again.'**
  String get resolverPlaybackFailed;

  /// No description provided for @cloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Harmony Cloud backup'**
  String get cloudBackup;

  /// No description provided for @cloudBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Securely sync your library, settings and downloaded-song inventory.'**
  String get cloudBackupDescription;

  /// No description provided for @cloudBackupPrompt.
  ///
  /// In en, this message translates to:
  /// **'Keep your Harmony data backed up and synchronized across devices?'**
  String get cloudBackupPrompt;

  /// No description provided for @cloudBackupEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable backup'**
  String get cloudBackupEnable;

  /// No description provided for @cloudBackupNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get cloudBackupNotNow;

  /// No description provided for @cloudBackupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up downloaded songs now'**
  String get cloudBackupNow;

  /// No description provided for @cloudBackupInProgress.
  ///
  /// In en, this message translates to:
  /// **'Backing up downloaded songs…'**
  String get cloudBackupInProgress;

  /// No description provided for @cloudBackupComplete.
  ///
  /// In en, this message translates to:
  /// **'Downloaded-song backup finished.'**
  String get cloudBackupComplete;

  /// No description provided for @cloudBackupWifiRequired.
  ///
  /// In en, this message translates to:
  /// **'Connect to Wi-Fi to back up downloaded songs.'**
  String get cloudBackupWifiRequired;

  /// No description provided for @cloudBackupFailed.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup failed. Try again.'**
  String get cloudBackupFailed;

  /// No description provided for @cloudBackupAuthenticationRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in again before backing up downloaded songs.'**
  String get cloudBackupAuthenticationRequired;

  /// No description provided for @cloudBackupPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup is not authorized for this account yet.'**
  String get cloudBackupPermissionDenied;

  /// No description provided for @cloudBackupServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup service is unavailable. Try again later.'**
  String get cloudBackupServiceUnavailable;

  /// No description provided for @cloudBackupNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup could not reach the service. Check your connection.'**
  String get cloudBackupNetworkFailure;

  /// No description provided for @cloudBackupLowBatteryTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery is low'**
  String get cloudBackupLowBatteryTitle;

  /// No description provided for @cloudBackupLowBatteryMessage.
  ///
  /// In en, this message translates to:
  /// **'Your battery is below 50%. Backing up downloaded songs may use significant power.'**
  String get cloudBackupLowBatteryMessage;

  /// No description provided for @cloudBackupAnyway.
  ///
  /// In en, this message translates to:
  /// **'Back up anyway'**
  String get cloudBackupAnyway;

  /// No description provided for @shareAndroidApp.
  ///
  /// In en, this message translates to:
  /// **'Share Harmony Music'**
  String get shareAndroidApp;

  /// No description provided for @shareAndroidAppDescription.
  ///
  /// In en, this message translates to:
  /// **'Share a direct link to the latest Android APK.'**
  String get shareAndroidAppDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hr':
      return AppLocalizationsHr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
