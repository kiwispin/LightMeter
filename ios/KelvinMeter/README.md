# Kelvin Meter iOS

Native iPhone prototype for estimating light color temperature from the camera.

## Current Features

- SwiftUI meter interface
- AVFoundation live camera preview
- Center-patch RGB sampling
- Estimated kelvin, tint, RGB, and relative light readouts
- Hold/live mode
- Camera exposure/white-balance lock toggle
- Neutral-card phone profile capture for Daylight, Tungsten, Cloudy, Shade, or a custom kelvin reference
- Saved per-device calibration profile with sample stability and confidence
- Raw vs corrected kelvin readout in the details sheet

## Running

Open `KelvinMeter.xcodeproj` in Xcode, select your Apple Developer team on the **KelvinMeter** target, then run on a real iPhone. The simulator cannot provide useful camera measurements.

If command-line builds fail with a license message, run this once in Terminal:

```sh
sudo xcodebuild -license
```

If Xcode reports that the iOS platform is not installed, open **Xcode > Settings > Components** and install the current iOS platform/runtime. This is required before `xcodebuild` can select a real iPhone destination.

## Accuracy Notes

This native version gives us more control than the web app, but it is still not a replacement for a calibrated color meter yet.

The current calibration flow trains a local iPhone profile by averaging live camera white-balance and center-patch readings from a neutral white/grey card. Good references are clean midday daylight, known tungsten/halogen light, or a custom source with a known kelvin value. LED, screen, mixed, bounced, or colored light can produce plausible but wrong numbers, so the app labels readings with confidence states such as estimated, calibrated, unstable, low light, or clipped.

Independent teardown and camera-review sources are useful for understanding the iPhone 16 Pro camera stack, but public sources do not provide the full spectral response, lens transmission, Apple ISP behavior, or per-device factory calibration needed for certified lux/CCT accuracy. The next serious accuracy step is a multi-point profile per iPhone/lens, ideally checked against known lights or a borrowed color meter.
