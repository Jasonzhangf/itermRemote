import 'encoding_policy_models.dart';

/// Built-in profile IDs.
class EncodingProfileIds {
  static const String textLatency = 'text_latency';
  static const String textQuality = 'text_quality';
  static const String balanced = 'balanced';
}

/// Built-in profiles.
class EncodingProfiles {
  static const EncodingProfile textLatency = EncodingProfile(
    id: EncodingProfileIds.textLatency,
    name: 'Text + Low Latency',
    description:
        'Prefer stable 15-30fps and low latency. Sacrifice resolution/quality first.',
  );

  static const EncodingProfile textQuality = EncodingProfile(
    id: EncodingProfileIds.textQuality,
    name: 'Text + Readability',
    description:
        'Prefer readability of terminal text. May drop fps before dropping resolution too much.',
  );

  static const EncodingProfile balanced = EncodingProfile(
    id: EncodingProfileIds.balanced,
    name: 'Balanced',
    description: 'Balanced tradeoff between fps, resolution, and quality.',
  );

  static const List<EncodingProfile> all = <EncodingProfile>[
    textLatency,
    textQuality,
    balanced,
  ];
}

