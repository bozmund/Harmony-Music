import 'dart:convert';

/// Wire protocol for the "Listen Together" feature.
///
/// Messages are plain JSON so the same encoding works over both the LAN
/// (WebSocket text frames) and Bluetooth/P2P (byte payloads) transports.
/// The protocol is intentionally tiny — we never send audio, only control
/// state (queue + current song + position + play/pause).
enum SessionMessageType {
  /// Guest -> host, sent right after connecting. Carries the guest's name and
  /// its local clock so the host can echo it back for round-trip estimation.
  hello,

  /// Host -> guest reply to [hello]. Echoes the guest clock and adds the host
  /// clock so the guest can estimate the host<->guest clock offset.
  helloAck,

  /// Host -> guests. Full ordered queue + the currently playing index.
  queueSync,

  /// Host -> guests. Lightweight playback state, sent on every change and as a
  /// periodic heartbeat.
  playbackSync,

  /// Guest -> host. A control request (play/pause/next/seek/...). The host
  /// performs it locally, which re-broadcasts state to everyone.
  command,

  /// Host -> guests. The current participant list.
  peerList,

  /// Either direction. Sender is leaving the session.
  bye,
}

SessionMessageType _typeFromName(String name) => SessionMessageType.values
    .firstWhere((t) => t.name == name, orElse: () => SessionMessageType.bye);

/// A single control action a participant can request.
///
/// Guests never mutate playback directly; they send a [SessionCommand] to the
/// host, the host executes it, and the resulting state broadcast converges
/// everyone (including the sender). This keeps a single writer and avoids
/// conflicting updates.
class SessionCommand {
  const SessionCommand(this.action, [this.args = const {}]);

  final String action;
  final Map<String, dynamic> args;

  static const actionPlay = 'play';
  static const actionPause = 'pause';
  static const actionPlayPause = 'playPause';
  static const actionNext = 'next';
  static const actionPrev = 'prev';
  static const actionSeek = 'seek';
  static const actionPlayByIndex = 'playByIndex';
  static const actionToggleShuffle = 'toggleShuffle';
  static const actionToggleLoop = 'toggleLoop';

  factory SessionCommand.play() => const SessionCommand(actionPlay);
  factory SessionCommand.pause() => const SessionCommand(actionPause);
  factory SessionCommand.playPause() => const SessionCommand(actionPlayPause);
  factory SessionCommand.next() => const SessionCommand(actionNext);
  factory SessionCommand.prev() => const SessionCommand(actionPrev);
  factory SessionCommand.seek(Duration position) =>
      SessionCommand(actionSeek, {'positionMs': position.inMilliseconds});
  factory SessionCommand.playByIndex(int index) =>
      SessionCommand(actionPlayByIndex, {'index': index});
  factory SessionCommand.toggleShuffle() =>
      const SessionCommand(actionToggleShuffle);
  factory SessionCommand.toggleLoop() => const SessionCommand(actionToggleLoop);

  Duration get seekPosition =>
      Duration(milliseconds: (args['positionMs'] as num?)?.toInt() ?? 0);

  int get index => (args['index'] as num?)?.toInt() ?? 0;

  Map<String, dynamic> toJson() => {'action': action, 'args': args};

  factory SessionCommand.fromJson(Map<String, dynamic> json) => SessionCommand(
    json['action'] as String,
    Map<String, dynamic>.from(json['args'] as Map? ?? const {}),
  );
}

/// Immutable snapshot of playback state broadcast by the host.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.songId,
    required this.index,
    required this.positionMs,
    required this.playing,
    required this.hostTimestampMs,
    this.shuffle = false,
    this.loop = false,
  });

  final String? songId;
  final int index;
  final int positionMs;
  final bool playing;

  /// Host monotonic wall-clock (ms since epoch) at the moment the snapshot was
  /// produced. Used together with the estimated clock offset to project the
  /// expected position on a guest.
  final int hostTimestampMs;
  final bool shuffle;
  final bool loop;

  Map<String, dynamic> toJson() => {
    'songId': songId,
    'index': index,
    'positionMs': positionMs,
    'playing': playing,
    'hostTimestampMs': hostTimestampMs,
    'shuffle': shuffle,
    'loop': loop,
  };

  factory PlaybackSnapshot.fromJson(Map<String, dynamic> json) =>
      PlaybackSnapshot(
        songId: json['songId'] as String?,
        index: (json['index'] as num?)?.toInt() ?? 0,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        playing: json['playing'] as bool? ?? false,
        hostTimestampMs: (json['hostTimestampMs'] as num?)?.toInt() ?? 0,
        shuffle: json['shuffle'] as bool? ?? false,
        loop: json['loop'] as bool? ?? false,
      );
}

/// A message on the wire. Carries its [type], the sender identity, and a
/// type-specific [data] payload.
class SessionMessage {
  const SessionMessage({
    required this.type,
    required this.senderId,
    required this.senderName,
    this.data = const {},
  });

  final SessionMessageType type;
  final String senderId;
  final String senderName;
  final Map<String, dynamic> data;

  // ---- Typed builders -------------------------------------------------------

  factory SessionMessage.hello({
    required String senderId,
    required String senderName,
    required int clientTimeMs,
  }) => SessionMessage(
    type: SessionMessageType.hello,
    senderId: senderId,
    senderName: senderName,
    data: {'clientTimeMs': clientTimeMs},
  );

  factory SessionMessage.helloAck({
    required String senderId,
    required String senderName,
    required int clientTimeMs,
    required int hostTimeMs,
  }) => SessionMessage(
    type: SessionMessageType.helloAck,
    senderId: senderId,
    senderName: senderName,
    data: {'clientTimeMs': clientTimeMs, 'hostTimeMs': hostTimeMs},
  );

  factory SessionMessage.queueSync({
    required String senderId,
    required String senderName,
    required List<Map<String, dynamic>> queue,
    required int index,
  }) => SessionMessage(
    type: SessionMessageType.queueSync,
    senderId: senderId,
    senderName: senderName,
    data: {'queue': queue, 'index': index},
  );

  factory SessionMessage.playbackSync({
    required String senderId,
    required String senderName,
    required PlaybackSnapshot snapshot,
  }) => SessionMessage(
    type: SessionMessageType.playbackSync,
    senderId: senderId,
    senderName: senderName,
    data: snapshot.toJson(),
  );

  factory SessionMessage.command({
    required String senderId,
    required String senderName,
    required SessionCommand command,
  }) => SessionMessage(
    type: SessionMessageType.command,
    senderId: senderId,
    senderName: senderName,
    data: command.toJson(),
  );

  factory SessionMessage.peerList({
    required String senderId,
    required String senderName,
    required List<Map<String, String>> peers,
  }) => SessionMessage(
    type: SessionMessageType.peerList,
    senderId: senderId,
    senderName: senderName,
    data: {'peers': peers},
  );

  factory SessionMessage.bye({
    required String senderId,
    required String senderName,
  }) => SessionMessage(
    type: SessionMessageType.bye,
    senderId: senderId,
    senderName: senderName,
  );

  // ---- Typed accessors ------------------------------------------------------

  int get clientTimeMs => (data['clientTimeMs'] as num?)?.toInt() ?? 0;
  int get hostTimeMs => (data['hostTimeMs'] as num?)?.toInt() ?? 0;

  int get queueIndex => (data['index'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get queue => ((data['queue'] as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  PlaybackSnapshot get snapshot => PlaybackSnapshot.fromJson(data);

  SessionCommand get command => SessionCommand.fromJson(data);

  List<Map<String, String>> get peers => ((data['peers'] as List?) ?? const [])
      .map((e) => Map<String, String>.from(e as Map))
      .toList();

  // ---- Serialization --------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'senderId': senderId,
    'senderName': senderName,
    'data': data,
  };

  factory SessionMessage.fromJson(Map<String, dynamic> json) => SessionMessage(
    type: _typeFromName(json['type'] as String? ?? ''),
    senderId: json['senderId'] as String? ?? '',
    senderName: json['senderName'] as String? ?? '',
    data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
  );

  String encode() => jsonEncode(toJson());

  List<int> encodeBytes() => utf8.encode(encode());

  static SessionMessage decode(String raw) =>
      SessionMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  static SessionMessage decodeBytes(List<int> bytes) =>
      decode(utf8.decode(bytes));
}
