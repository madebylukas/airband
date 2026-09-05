# AirBand

AirBand turns an iPhone into a camera-driven musical instrument. Vision tracks both hands down to the fingers while ARKit tracks facial expression. A live waveform shows the sound leaving the synth.

Every pitch is quantized to D minor pentatonic, so improvisation stays musical. Tracking and synthesis run entirely on-device; camera frames are never stored or transmitted.

## Run

Open `AirBand.xcodeproj` in Xcode, choose a Face ID iPhone, and press Run. Camera mode requires a physical device for useful testing. Touch mode works in Simulator.

The project targets iOS 18 and uses SwiftUI, ARKit, Vision, SceneKit, and AVAudioEngine. Its Liquid Glass controls activate on iOS 26, with a material fallback on earlier supported versions.

## Controls

- Left-hand height: pitch or song key
- Left-hand horizontal position: octave
- Left-hand outward rotation: low-pass muffle
- Right-hand height: tempo in Song and Drums
- Right-hand outward rotation: distortion
- Distance between hands: volume in Free mode
- Smile: brightness
- Open mouth: vibrato
- Left wink: supplied fart sample; cymbal in Drums
- Right wink: supplied ding sample; kick in Drums

Free mode is a pentatonic instrument. Song mode generates a transposable melody, bass line, and beat. Drums keeps the rhythm section and maps winks to percussion.

## Verification

Run `./scripts/test.sh` for musical mapping, adaptive point filtering, pitch hysteresis, separate wink identity, sequencer output, DSP stability, and audio-envelope checks. Build with:

```sh
xcodebuild -project AirBand.xcodeproj -scheme AirBand \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Release notes

The bundle identifier is `com.lukaswinter.AirBand` and automatic signing uses team `3N88SJUYYR`. Before App Store submission, verify gesture thresholds and audio latency on a supported Face ID iPhone, create the App Store Connect record, capture device screenshots, and provide a public privacy-policy URL.
