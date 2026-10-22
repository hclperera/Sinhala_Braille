# InfoX Offline

An offline Flutter Sinhala Braille reader for Android and iOS. Capture manually
with continuous torch lighting, or select an existing image. Recognition runs on
the device: YOLOv8n page crop → grayscale/bilateral/CLAHE → SAHI-style overlapping
YOLOv8s inference → class-aware merging → backend grid reconstruction → Sinhala
text, with play/stop speech controls.

The trained ONNX models and Sinhala font are bundled. No account or server is
required. The original Python pipeline is frozen under `tools/reference/` for
comparison; it is not used by the mobile runtime.

## Run on Android

```powershell
flutter pub get
flutter run
```

Enable USB debugging and accept your computer on the phone. The first native
build downloads and compiles OpenCV, so it needs internet on the development
computer. The installed app processes images offline.

```powershell
flutter build apk --debug --target-platform android-arm64
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`.

## Validation

```powershell
dart tools/check_core.dart
dart tools/check_grouping.dart
dart tools/check_speech.dart
flutter analyze
flutter test --no-test-assets
```

The standalone checks compare translation, rotated grids, and slicing against
4,614 Python-reference cases, plus IOS/IoU merging checks. Fourteen additional
full-backend cases cover automatic and forced curved-page fits, calibration,
line/segment refinement, classification recovery and rejection paths. Speech
checks cover offline voice selection and long-page chunking.
Flutter tests also invoke native dependency hooks, which require a host CMake
and C++ toolchain. The standalone check does not require native libraries.

No real Braille test photos were available during initial implementation.
Recognition accuracy, phone processing time and torch behavior need device
validation. The complete backend grouping algorithm is ported, including its
curved-page fallback and optional refinement/recovery. Backend defaults are kept;
experimental refinement/recovery remains opt-in through `GridConfig`.
iOS needs a Mac and Xcode for building and physical-device validation.

Speech requires an installed Sinhala voice. Android voices that require a network
or have uninstalled voice data are excluded. If no offline voice is available,
the app explains this and provides a voice recheck action; it never falls back to
network synthesis or reads Sinhala using an unrelated language.

See [implementation details and phone testing](docs/IMPLEMENTATION.md).

Results can be saved locally with their source photo and reopened from Saved
scans. Correct text allows manual fixes before copying, speaking or saving;
saved metadata retains the original recognition output. Deleting a saved scan
removes its stored photo and text. Uninstalling the app removes local scans.
The replacement character `�` indicates an uncertain or unsupported Braille cell,
not a missing Sinhala font glyph; check the photo and recognition notes.
Run `dart tools/check_scan_store.dart` to check persistence and failed-save cleanup.

Sinhala text uses a bundled static Regular instance of Noto Sans Sinhala 2.006
from the official Google Fonts repository. This replaces the older 2.002 font
whose vowel-sign classifications cause zero-width overlap in modern shaping
engines. Results, selection, correction, saved text and TTS all use Unicode
without legacy FM conversion. Provenance and SHA-256 hashes are recorded in
`assets/fonts/NotoSansSinhala-source.json`.

## Kotlin build tooling recovery

If a build reports `BuildToolsApiClasspathEntrySnapshotTransform` followed by
`ClassNotFoundException: org.jetbrains.org.objectweb.asm.tree.ClassNode` after an
interrupted compiler download, verify the compiler dependency and restart Gradle:

```powershell
cd android
.\gradlew.bat --stop
cd ..
flutter run
```

The affected compiler JAR on the initial development machine was restored and
checksum-verified; a fresh Gradle process successfully compiled Flutter's Gradle
plugin. Model changes are unrelated to this tooling error.

If OpenCV's CMake download fails with an HTTP/2 stream error, download its
matching source archive over HTTP/1.1 and configure the existing Android cache:

```powershell
New-Item -ItemType Directory -Force .tooling | Out-Null
curl.exe -4 --http1.1 --fail --location https://codeload.github.com/opencv/opencv/tar.gz/refs/tags/4.13.0 --output .tooling/opencv-4.13.0.tar.gz
python tools/use_local_opencv.py .tooling/opencv-4.13.0.tar.gz
flutter build apk --debug --target-platform android-arm64
```

Run this after the first Android build has created the native cache. The helper
extracts source inside the workspace and configures CMake to use it; it does not
modify the globally installed Dart package. The first native compilation takes
longer than subsequent builds. Keep `.tooling/native_sources` while reusing that
cache, and match the archive version to the installed dartcv4 package.
