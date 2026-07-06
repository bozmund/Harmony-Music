/// A one-time question shipped with a specific release. The home screen
/// shows it once on first launch after updating; the answered prompt id is
/// persisted so it never returns.
class ReleasePromptConfig {
  const ReleasePromptConfig({required this.id});

  /// Unique, stable identifier for this prompt (also the persistence key).
  final String id;
}

/// The prompt for the CURRENT release, or null when this release ships
/// without one — nothing is shown then. Point it at a new config (and a new
/// dialog body in release_prompt_dialog.dart) whenever a future release
/// needs to ask the user something once.
///
/// 6.0.0: stable became the default update channel, so existing users —
/// who were all effectively on rolling — pick their channel explicitly.
const ReleasePromptConfig? currentReleasePrompt = ReleasePromptConfig(
  id: 'channel-choice-6.0.0',
);
