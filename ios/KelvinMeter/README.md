# Kelvin Meter iOS

Native iPhone prototype for estimating light color temperature from the camera.

## Current Features

- SwiftUI meter interface
- AVFoundation live camera preview
- Center-patch RGB sampling
- Estimated kelvin, tint, RGB, and relative light readouts
- Hold/live mode
- Camera exposure/white-balance lock toggle
- Calibrate current neutral-card reading to 5600K
- Saved per-device calibration offset

## Running

Open `KelvinMeter.xcodeproj` in Xcode, select your Apple Developer team on the **KelvinMeter** target, then run on a real iPhone. The simulator cannot provide useful camera measurements.

If command-line builds fail with a license message, run this once in Terminal:

```sh
sudo xcodebuild -license
```

If Xcode reports that the iOS platform is not installed, open **Xcode > Settings > Components** and install the current iOS platform/runtime. This is required before `xcodebuild` can select a real iPhone destination.

## Accuracy Notes

This native version gives us more control than the web app, but it is still not a replacement for a calibrated color meter yet. The next serious accuracy step is a multi-point calibration profile for the iPhone 16 Pro camera you intend to use, ideally checked against known lights or a borrowed color meter.
