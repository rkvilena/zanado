# Development guide

How to set up, run, test, and build Zanado from source. All commands are plain shell commands (POSIX-style paths shown for Git Bash on Windows).

## Toolchain

Zanado is a Flutter app with a small Android native layer (MediaStore integration via a MethodChannel). The verified toolchain combination:

| Component | Version |
|---|---|
| Flutter | 3.47.7 |
| Dart | 3.13.5 |
| Gradle | 9.3.1 |
| Android Gradle Plugin | 9.1.0 |
| Kotlin | 2.4.0 |
| JDK | 21 |

Do not upgrade any of these mid-feature — version drift is the most common cause of new build failures. Check `flutter doctor -v` against this table first when a build breaks.

## Prerequisites

- **Flutter SDK** with the Dart SDK above.
- **Android toolchain** (SDK + build tools) for Android builds; a physical device with USB debugging for real transfer testing.
- **Visual Studio Build Tools (C++ workload)** for Windows builds.
- **JDK 21** (other versions may work, but 21 is the verified combination with the toolchain above).
- **Both devices on the same Wi-Fi** for two-target transfer testing.

## Setup

```bash
git clone <repository-url>
cd zanado
flutter doctor -v          # confirm no critical Android/Windows issues
flutter pub get            # resolves dependencies from pubspec.lock
```

## Daily workflow

```bash
flutter devices            # confirm the phone/desktop is listed
flutter run                # hot-reload loop; builds + installs debug APK automatically
flutter run -d <device_id> # when more than one device/emulator is attached

flutter analyze            # static analysis — must be zero issues before delivery
flutter test               # unit tests
```

### Transfer testing on two devices

1. Connect Android and Windows to the same Wi-Fi.
2. Start Zanado on the sender (Android or Windows) and pick a file.
3. Scan the QR on the Android receiver, or paste the full `zanado://` URI on Windows.
4. Wait for checksum verification; the file lands in `Downloads/zanado` on the receiver.

## Build commands

| Target | Command | Output |
|---|---|---|
| Android debug | `flutter build apk --debug` | `build/app/outputs/flutter-apk/app-debug.apk` |
| Android release | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Windows debug | `flutter build windows --debug` | `build/windows/x64/runner/Debug/zanado.exe` |
| Windows release | `flutter build windows --release` | `build/windows/x64/runner/Release/zanado.exe` |

Install manually:

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat | grep -i flutter   # crash/log debugging on the phone
```

## Clean-build process

Builds on Windows can fail due to environment issues (Windows file locks, stale Gradle daemons) rather than code problems. Use this controlled, repeatable procedure; diagnose failures by category — never by blind repeated cleaning.

```bash
# 1. Capture environment (when versions may have changed)
flutter --version && dart --version && java -version
flutter doctor -v

# 2. Record state (read-only)
flutter pub deps

# 3. Stop Gradle daemons (close Android Studio / terminals holding build files first)
cd android && ./gradlew --stop && cd ..

# 4. Clean generated state (never touches source)
flutter clean
rm -rf android/.gradle android/app/build build

# 5. Re-resolve dependencies (no upgrades!)
flutter pub get

# 6. Validate Dart before Gradle
flutter analyze   # must be zero issues
flutter test      # must be all-pass

# 7. Build through Flutter
flutter build apk --debug

# 8. Verify the artifact
ls -lh build/app/outputs/flutter-apk/app-debug.apk
```

## Diagnosing build failures

When a build fails, run Gradle directly to get the full error — Flutter's wrapper output truncates it. Capture the full log to a file rather than piping through `tail`/`head`:

```bash
cd android && ./gradlew assembleDebug --stacktrace --info > ../gradle_build.log 2>&1 && cd ..
```

Classify the failure by category before applying any fix:

| Category | Signature | Targeted fix |
|---|---|---|
| Java/AGP mismatch | version incompatibility text | check toolchain table; do not bump mid-feature |
| Dependency download | network/repo errors in log | check network, Gradle cache; retry once |
| Windows file lock | `mergeDebugJavaResource` / `base.jar` busy | stop daemons, clean, rebuild (see below) |
| SDK/license | "SDK location not found", license errors | fix `android/local.properties`; `flutter doctor --android-licenses` |
| Plugin compile | errors inside a pub package | check package version vs. toolchain |
| App compile | errors in `lib/` or generated Kotlin | fix code, not the build system |

## Known failure modes

### 1. `mergeDebugJavaResource` fails — `base.jar` locked / busy daemon

**The most common build failure on Windows.** Leftover Gradle daemons hold Windows file locks on `build/app/intermediates/**`.

```bash
cd android && ./gradlew --stop && cd ..
flutter clean
flutter pub get
flutter build apk --debug
```

Do **not** delete the global Gradle cache (`~/.gradle`) for this error — that forces a full re-download.

### 2. Device shows `unauthorized`

Unlock the phone and allow USB debugging. If no prompt appears: Developer options → *Revoke USB debugging authorizations* → unplug/replug → restart ADB. Set USB mode to *File transfer*.

### 3. `more than one device/emulator`

Target a specific device: `flutter run -d <device_id>`, `adb -s <device_id> install -r <apk>`. Clear ghost/offline entries: `adb kill-server && adb start-server && adb devices`.

### 4. `SDK location not found`

Fix or create `android/local.properties`:

```properties
sdk.dir=C:\\path\\to\\Android\\Sdk
```

Run `flutter doctor -v` to see which SDK Flutter picks.

### 5. Release-mode signature mismatch

When switching between debug and release installs: `adb uninstall com.zanado.zanado` first.

### 6. Release build needs INTERNET permission

Flutter adds it for debug automatically. For release, ensure `<uses-permission android:name="android.permission.INTERNET"/>` is present in `android/app/src/main/AndroidManifest.xml`, and both devices must be on the same Wi-Fi for transfer testing.

### 7. Kotlin compile crash — `IllegalArgumentException: this and base files have different roots`

Kotlin's incremental compiler cannot compute a relative path when the pub cache and the project live on different drive roots (common on Windows). The project disables Kotlin incremental compilation (`kotlin.incremental=false` in `android/gradle.properties`) — keep it there. Alternative fix: move the pub cache to the same drive as the project via `PUB_CACHE`.

## Testing

```bash
flutter analyze    # zero issues expected
flutter test       # 136 tests pass
```

Widget tests must reset `debugDefaultTargetPlatformOverride` at the end of the test body (not in a tearDown) — the binding invariant check runs before tearDowns.

## Architecture notes for contributors

- Dependency direction is strictly `features → domain ← data`; see [architecture.md](architecture.md).
- Any structural change (architecture, data flow, module boundaries, platform channels, folder layout) must be reflected in the documentation and phase records.
- Never do multi-GB synchronous I/O on the Android main thread inside a MethodChannel handler — see [architectural-decisions.md](architectural-decisions.md) ADR-012.
