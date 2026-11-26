import 'package:marquee/engine/audio_fx.dart';
import 'package:marquee/engine/models/settings.dart';
import 'package:test/test.dart';

void main() {
  group('sound profiles', () {
    test('sends mpv nothing when everything is off', () {
      expect(audioFilterChain(normalize: false, preset: EqPreset.flat), '');
    });

    test('has a gain for every band of every preset', () {
      for (final p in EqPreset.values) {
        expect(eqGains(p), hasLength(kEqBands.length), reason: p.name);
        // No pre-amp: a boost past 6 dB would clip a loud film.
        expect(eqGains(p).every((g) => g >= -12 && g <= 6), isTrue, reason: p.name);
      }
      expect(eqGains(EqPreset.flat).every((g) => g == 0), isTrue);
    });

    test('evens out loud and quiet parts with dynaudnorm alone', () {
      expect(
        audioFilterChain(normalize: true, preset: EqPreset.flat),
        'lavfi=[dynaudnorm=f=250:g=11:p=0.9:m=8]',
      );
    });

    test('builds one biquad per band that is off zero', () {
      expect(
        audioFilterChain(normalize: false, preset: EqPreset.bassBoost),
        'lavfi=[equalizer=f=31:t=o:w=1:g=5,equalizer=f=62:t=o:w=1:g=4,'
        'equalizer=f=125:t=o:w=1:g=3,equalizer=f=250:t=o:w=1:g=1]',
      );
      expect(
        audioFilterChain(normalize: false, preset: EqPreset.trebleBoost),
        'lavfi=[equalizer=f=2000:t=o:w=1:g=1,equalizer=f=4000:t=o:w=1:g=3,'
        'equalizer=f=8000:t=o:w=1:g=4,equalizer=f=16000:t=o:w=1:g=5]',
      );
      expect(
        audioFilterChain(normalize: false, preset: EqPreset.voiceBoost),
        'lavfi=[equalizer=f=31:t=o:w=1:g=-2,equalizer=f=62:t=o:w=1:g=-2,'
        'equalizer=f=125:t=o:w=1:g=-1,equalizer=f=500:t=o:w=1:g=1,'
        'equalizer=f=1000:t=o:w=1:g=3,equalizer=f=2000:t=o:w=1:g=4,'
        'equalizer=f=4000:t=o:w=1:g=3,equalizer=f=8000:t=o:w=1:g=1]',
      );
    });

    test('puts the normaliser after the equaliser', () {
      expect(
        audioFilterChain(normalize: true, preset: EqPreset.nightMode),
        'lavfi=[equalizer=f=31:t=o:w=1:g=-6,equalizer=f=62:t=o:w=1:g=-5,'
        'equalizer=f=125:t=o:w=1:g=-3,equalizer=f=250:t=o:w=1:g=-1,'
        'equalizer=f=1000:t=o:w=1:g=2,equalizer=f=2000:t=o:w=1:g=3,'
        'equalizer=f=4000:t=o:w=1:g=2,equalizer=f=16000:t=o:w=1:g=-1,'
        'dynaudnorm=f=250:g=11:p=0.9:m=8]',
      );
    });
  });
}
