# Vendored google_mlkit_commons 0.12.0

Copied from pub.dev and patched in `ios/Classes/MLKVisionImage+FlutterPlugin.swift`:
camera frames passed as bytes are wrapped in a `CMSampleBuffer` and handed to
ML Kit directly, instead of being rendered through a new `CIContext` into a
`CGImage`/`UIImage` on every frame. Everything else is unchanged.

Used through `dependency_overrides` in the app's `pubspec.yaml`.
