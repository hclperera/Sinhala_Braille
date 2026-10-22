# InfoX offline implementation

## Scope

Android and iOS Flutter application. Manual capture with continuous torch, gallery
selection, page crop, grayscale/bilateral/CLAHE preprocessing, SAHI-style YOLOv8s
dot inference, full backend grid reconstruction, Sinhala text and manual TTS
play/stop. No runtime network, accounts, history, automatic capture or camera
guidance.

The original Python services and selected UI files are frozen under
`tools/reference/`; exact upstream commits are in `revisions.json`. They are
reference sources, not shipped executable services. Models were supplied locally
by the project owner. The Sinhala font's license is bundled beside the font.

## Runtime choice

Initial CPU baseline: ONNX models through OpenCV DNN using `opencv_dart`/`dartcv4`.
This shares OpenCV image processing with the existing backend and avoids separate
native inference and preprocessing engines. Models are static float32, batch one,
640 square, ONNX opset 12, without embedded NMS. No quantization before accuracy
validation. OpenCV's `dnn` module must be included in pubspec hook configuration.

Model files and the Sinhala font are bundled. Models are copied to application
support storage on first use using versioned filenames. Recognition runs in a
worker isolate; no Flutter plugin calls are made from that worker. Slices run
sequentially to avoid multiplying the model's working memory. Cancellation kills
the worker; native calls may finish their current operation before termination.

## Pipeline parameters

- Honor EXIF orientation on decode; do not downsample source pages for inference.
- Page detection confidence 0.6, highest-confidence crop, floor/ceil and clamp bounds.
- No detected page: fail with retry instructions; no silent full-image fallback.
- BGR to gray, bilateral (9, 75, 75), CLAHE (clip 2, tiles 8x8), gray to BGR.
- SAHI-style 640x640 slices, overlap 0.2, shifted final edge slices.
- Letterbox to 640x640 with value 114, RGB float32 /255, CHW input.
- Dot confidence 0.25, per-inference class-aware IoU NMS 0.7, max 3500.
- Full-image pass when the page requires multiple slices (SAHI behavior).
- Global class-aware NMS, IOS 0.3, no page-wide 3500 cap.
- Front class 2, back class 1, InfoX class 0; retain classes until grouping.
- Regular grouping tolerance 0.28, minimum accepted fraction 0.90, six-dot
  column-major bit order, preserve blank cells between occupied cells and lines.
- Preserve the backend's automatic fallback to a smooth polynomial page warp,
  distributed spatial seeds, derivative/Jacobian guards and held-out validation.
- Preserve optional robust line refinement, regularized segment bends and
  auditable back-labelled dot recovery. These options retain the backend's
  default-off settings and quality gates; all are available through GridConfig.
- Use a native Dart KD-tree for exact neighbor queries and pivoted Householder QR
  for least-squares fits instead of requiring NumPy/SciPy on the phone. Keep cell
  sites, collision evidence, rejected detections and review flags in diagnostics.
- Sinhala literary translation ported from the original decoder, including
  prefixes, digits, vowel signs, explicit Roman labels and ambiguity warnings.

## Current limits

No real Braille test photographs were available during initial implementation.
Synthetic checks are regression/compatibility tests, not recognition accuracy.
The grouping port matches the frozen backend on 14 additional synthetic cases,
including curved fits with accepted local models and recovered back-labelled
dots. This does not establish accuracy on real pages. All retained points now
participate in skew estimation. Static square letterboxing must be compared with the
original PyTorch runtime's rectangular inference using real photographs.

Torch availability and camera lifecycle need physical-device testing. Android
builds target arm64 initially. iOS source is configured, but a Mac, Xcode and an
iPhone are needed to build and validate iOS. No iOS readiness claim is made.

The camera requests continuous autofocus when opened. On cameras supporting
focus points, tap inside the preview to choose a focus area; the yellow indicator
shows the requested point, not a confirmed focus lock. Reset autofocus restores
the default focus area. Focus requests are serialized with capture and lifecycle
operations, and capture waits for an active focus request. Fixed-focus cameras
remain usable. Focus accuracy and response time require device testing.

## Reproducible checks

1. `python tools/prepare_models.py`: export copies of the supplied models,
   validate ONNX and compare raw outputs with PyTorch on deterministic input.
   Originals are never modified. Manifest includes class metadata and SHA-256s.
2. `python tools/generate_fixtures.py`: generate expectations with frozen Python
   grouping/translation and the installed SAHI slicing implementation.
3. `dart tools/check_core.dart`: run pure Dart comparisons without native builds.
   `python tools/generate_grouping_fixtures.py` and `dart tools/check_grouping.dart`
   additionally verify the complete grouping pipeline, including physical cell
   site coordinates against Python. `dart tools/check_speech.dart` verifies voice
   filtering and input chunking without native speech services.
4. `flutter analyze` and `flutter test`: static checks and regression tests.
5. `flutter build apk --release --target-platform android-arm64`: test APK.

Python tooling requires ultralytics, torch, onnx, opencv-python, sahi, numpy,
scipy and python-dotenv; these were already installed on the development machine.

## First phone test

Install the test APK. Enable airplane mode, launch the app, grant camera access,
and capture a flat Braille page with the entire page visible. Check that the torch
stays on through capture and turns off afterward. Repeat using a gallery image.
Try cancel, denied permission, app background/resume and a non-Braille photo.
Record the displayed result, processing time, phone model and Android version.
Compare the Sinhala text with the physical page's known text.

Keep original photos in `test_images/` (gitignored), then run
`python tools/reference_scan.py test_images/page.jpg` for a Python baseline.
Successful app scans write temporary page preview and diagnostics in app-private
cache. They are not cloud uploads or user-facing saved history.

## Speech playback

The result screen has Play Sinhala text / Stop reading controls. Playback uses
flutter_tts with an explicit Sinhala voice. Android selection requires the voice
to report no network requirement and no `notInstalled` feature. On iOS, select
only an available Sinhala system voice by its identifier. Voice availability and
actual airplane-mode playback require physical-device validation.

Long results are split below platform input limits at word/grapheme boundaries.
Playback stops when a new image is opened, the app leaves the foreground, or the
reader is disposed. Missing voices are explained with a recheck action. There is
no cloud fallback and no bundled Sinhala speech model in this version. A phone
without a suitable installed Sinhala voice needs voice installation or a future
bundled synthesis engine before offline audio is available.
