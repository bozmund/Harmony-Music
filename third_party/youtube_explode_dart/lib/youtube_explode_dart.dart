/// Provides all the APIs implemented by this library.
library;

export 'src/channels/channels.dart';
export 'src/common/common.dart';
export 'src/exceptions/exceptions.dart';
export 'src/playlists/playlists.dart';
// FORK PATCH: upstream keeps the JS challenge solver interfaces under src/, so
// an app cannot supply its own without reaching into package internals. Harmony
// must: 3.x ships only `DenoEJSSolver`, which starts an external `deno` process
// — impossible on Android/iOS, where there is no such binary and W^X forbids
// executing one. Exporting the interface lets the app inject a QuickJS-backed
// solver instead. Worth upstreaming so this patch can be dropped.
export 'src/reverse_engineering/challenges/ejs/base_ejs_solver.dart';
// EJSBuilder too: the modules are fetched over the network, and the app resolves
// each song in a fresh isolate. Without access to the builder, every song would
// re-download the ~150KB bundle; the app fetches it once and passes it in.
export 'src/reverse_engineering/challenges/ejs/ejs.dart';
export 'src/reverse_engineering/challenges/js_challenge.dart';
export 'src/reverse_engineering/youtube_http_client.dart';
export 'src/search/search.dart';
export 'src/videos/videos.dart';
export 'src/youtube_explode_base.dart';
