// The sound profiles as an mpv `af` value: a 10-band equaliser (one lavfi `equalizer` biquad
// per band that is off zero) and, for "even out loud and quiet parts", `dynaudnorm`. Both are
// LGPL libavfilter filters. A libmpv build without them refuses the chain; the player layer
// reads `af` back and says so once.
import 'models/settings.dart';

/// Octave-spaced band centres, in Hz.
const List<int> kEqBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// Gain per band of [kEqBands], in dB. Boosts stay small: there is no pre-amp, so a large one
/// would clip a loud film.
List<int> eqGains(EqPreset preset) => switch (preset) {
  EqPreset.flat => const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  // Dialogue lives between 1 and 4 kHz; the rumble under it steps back.
  EqPreset.voiceBoost => const [-2, -2, -1, 0, 1, 3, 4, 3, 1, 0],
  EqPreset.bassBoost => const [5, 4, 3, 1, 0, 0, 0, 0, 0, 0],
  EqPreset.trebleBoost => const [0, 0, 0, 0, 0, 0, 1, 3, 4, 5],
  // Late at night: what carries through walls goes down, speech stays clear.
  EqPreset.nightMode => const [-6, -5, -3, -1, 0, 2, 3, 2, 0, -1],
};

/// A gentle, fast-acting normaliser: quiet speech comes up, an explosion does not jump out.
const String kNormalizeFilter = 'dynaudnorm=f=250:g=11:p=0.9:m=8';

/// The mpv `af` value for these choices, or '' when everything is off.
String audioFilterChain({required bool normalize, required EqPreset preset}) {
  final gains = eqGains(preset);
  final filters = [
    for (var i = 0; i < kEqBands.length; i++)
      if (gains[i] != 0) 'equalizer=f=${kEqBands[i]}:t=o:w=1:g=${gains[i]}',
    if (normalize) kNormalizeFilter,
  ];
  // One lavfi graph: the brackets keep its commas and colons away from mpv's own parser.
  return filters.isEmpty ? '' : 'lavfi=[${filters.join(',')}]';
}
