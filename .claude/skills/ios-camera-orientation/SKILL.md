---
name: ios-camera-orientation
description: Orientation, capture-rotation and counter-rotating-chrome facts for frmr's portrait-locked camera screen. Read before touching rotation, RAW development, the capture session or landscape chrome.
---

# frmr camera orientation — facts, not suggestions

These are lessons from v2 and the post-v2 landscape work. Breaking them breaks the app in ways the simulator cannot show.

## Two different orientation enums

- `UIDeviceOrientation`: how the phone is physically held. Includes `.faceUp`, `.faceDown`, `.unknown`.
- `UIInterfaceOrientation`: how the UI is drawn.
- Their landscape cases are **mirror images**: `UIDeviceOrientation.landscapeLeft` corresponds to `UIInterfaceOrientation.landscapeRight`, and vice versa.
- Mixing them is the classic cause of "it rotates the wrong way on device". **Check this first** for v3-5 (edge mapping) and the counter-rotation sign.

## Interface, preview and capture are three separate rotations

**Interface.** frmr locks the camera screen to portrait.
- An AppDelegate implements `application(_:supportedInterfaceOrientationsFor:)`.
- `UIWindowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))` (iOS 16+) makes the change apply immediately.
- Other tabs unlock on disappear.

**Preview.** The interface never rotates, so the `AVCaptureVideoPreviewLayer` connection must not be re-angled.
- Do **not** apply `videoRotationAngleForHorizonLevelPreview` on the camera screen.
- Doing so would shift the composition under the user's hand, which is exactly what the portrait lock exists to prevent.

**Capture.** The saved photo must be upright relative to gravity.
- Use `AVCaptureDevice.RotationCoordinator` (iOS 17+).
- Immediately before each capture, set the photo output connection's `videoRotationAngle` from `videoRotationAngleForHorizonLevelCapture`.
- Guard with `isVideoRotationAngleSupported(_:)`. An unsupported angle raises an Objective-C exception that Swift cannot catch.
- The coordinator holds its device weakly. Rebuild it on every camera or lens switch.
- Its KVO fires on the main queue.
- Never use the deprecated `videoOrientation`.

## RAW and orientation

- Develop RAW in sensor space (`CIRAWFilter.orientation = .up`), then tag the resulting `UIImage` with the capture's EXIF orientation.
- `CGImagePropertyOrientation` and `UIImage.Orientation` share case names but **not raw values**. Bridge through an explicit `switch`, never `rawValue`.
- `UIImage(cgImage:)` without an orientation argument hardcodes `.up`.

## Counter-rotating chrome in a portrait-locked UI

`.rotationEffect` repaints but does not reflow: the parent still reserves the unrotated size. Consequences:

- Rotate each control individually, never a container.
- A wide-and-short view swings its content off-position when rotated. Anchor trailing/leading items with `.overlay(alignment:)` on a non-rotating parent, not with `HStack { Spacer(); … }`.
- Controls never move, stack or reflow with orientation (v3 F2/F4 superseded). Make every control a fixed-size shape (44pt circle or square) and rotate only its glyph inside a static backing, so nothing overflows. Do not reintroduce a stacked/edge-strip layout.
- Face-up, face-down and unknown hold the last known value.

## Gesture and session discipline

- All `lockForConfiguration()` work runs on `CaptureSession`'s private queue.
- Tap points convert through `previewLayer.captureDevicePointConverted(fromLayerPoint:)`.
- Guard every capability (`isFocusPointOfInterestSupported`, exposure modes, zoom range) and fail silently only where the spec says so.
- The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pipeline types (`CaptureSession`, `ImageProcessor`, `StripGenerator`, `Constants`) are explicitly `nonisolated`; keep that pattern.

## What the simulator cannot prove

No camera, no orientation sensor, no haptics. Anything in those areas is **"unverified on device"** until a human photographs it. Never claim otherwise.
