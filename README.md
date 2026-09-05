# AirBand

AirBand turns an iPhone into a camera-driven musical instrument. Raise a hand for pitch, spread two hands for volume, rotate a palm for distortion, smile for brightness, open your mouth for vibrato, and wink for one strategically undignified sound.

Every pitch is quantized to D minor pentatonic, so improvisation stays musical. Tracking and synthesis run entirely on-device; camera frames are never stored or transmitted.

## Run

Open `AirBand.xcodeproj` in Xcode, choose a Face ID iPhone, and press Run. Camera mode requires a physical device for useful testing. Touch mode works in Simulator.

The project targets iOS 18 and uses SwiftUI, ARKit, Vision, SceneKit, and AVAudioEngine. Its Liquid Glass controls activate on iOS 26, with a material fallback on earlier supported versions.

## Controls

- Hand height: pitch
- Distance between hands: volume
- Palm rotation: distortion
- Smile: brightness
- Open mouth: vibrato
- Deliberate wink: fart

## Verification

Run `./scripts/test.sh` for musical mapping, palm rotation, wink rejection, DSP stability, and audio-envelope checks. Build with:

```sh
xcodebuild -project AirBand.xcodeproj -scheme AirBand \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Release notes

The bundle identifier is `com.lukaswinter.AirBand` and automatic signing uses team `3N88SJUYYR`. Before App Store submission, verify gesture thresholds and audio latency on a supported Face ID iPhone, create the App Store Connect record, capture device screenshots, and provide a public privacy-policy URL.
