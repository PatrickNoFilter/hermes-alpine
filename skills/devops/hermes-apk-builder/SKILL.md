---
name: hermes-apk-builder
title: "Hermes APK Builder"
description: "Build a standalone Hermes Agent APK for Android with embedded terminal emulator + SSH server"
trigger: "User asks for an APK, Hermes Android app, or standalone Android build"
---

# Hermes APK Builder

Builds a standalone Android APK packaging the Hermes Agent as a terminal app with copy/paste, command history, SSH server, foreground service, and boot auto-start.

## Prerequisites (ARM64 environment, e.g. Termux PRoot)

```bash
# JDK 17
apt-get install -y openjdk-17-jdk

# Android SDK + NDK
ANDROID_HOME=/opt/android-sdk
mkdir -p $ANDROID_HOME
curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmd.zip
unzip -q /tmp/cmd.zip -d $ANDROID_HOME
yes | $ANDROID_HOME/cmdline-tools/bin/sdkmanager --sdk_root=$ANDROID_HOME --install \
  "platforms;android-34" "build-tools;34.0.0" "ndk;27.0.12077973"

# QEMU user (for x86_64 SDK binaries on ARM64) + multiarch libs
apt-get install -y qemu-user zip unzip
dpkg --add-architecture amd64
apt-get update && apt-get install -y libc6:amd64 libstdc++6:amd64 zlib1g:amd64

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
export PATH=$JAVA_HOME/bin:$PATH
```

## Project Structure

```
hermes-apk/
├── build.sh                  # Build script
├── debug.keystore            # Generated on first build
├── output/hermes.apk         # Final APK
├── tool-wrappers/            # QEMU wrappers
└── app/
    ├── AndroidManifest.xml
    ├── res/ (layout, values, drawable, xml)
    └── src/com/hermes/agent/
        ├── MainActivity.java     # Terminal emulator UI
        ├── HermesService.java    # Foreground service
        ├── SettingsActivity.java # SSH config
        └── BootReceiver.java     # Auto-start on boot
```

## Build Steps

**1. QEMU wrappers**: `aapt2` & `zipalign` are x86_64 ELF → wrap with `qemu-x86_64`. `d8` / `aapt` are shell scripts → run natively.

**2. Resource compilation**: `aapt2 compile` each XML → `.flat` files.

**3. Link + generate R.java**: `aapt2 link --java $GEN` produces `R.java` for resource IDs. Include `$GEN` in javac classpath.

**4. Java → DEX**: `javac` → `d8` (shell script, runs via Java).

**5. Package**: `zip` classes.dex into APK.

**6. Align**: `zipalign` — must run BEFORE signing (see Pitfalls).

**7. Sign with apksigner (v2/v3 APK signatures)**: `apksigner` — a Java JAR wrapper that runs natively on ARM64 (no QEMU needed). Produces v1+v2+v3 signatures:

```bash
KS=debug.keystore
$BT/apksigner sign \
    --ks "$KS" --ks-pass pass:android \
    --ks-key-alias androiddebugkey \
    --v1-signing-enabled true \
    --v2-signing-enabled true \
    --v3-signing-enabled true \
    --out output/hermes.apk \
    output/aligned.apk
```

**8. Verify signing**:

```bash
$BT/apksigner verify --verbose output/hermes.apk
# Expected: "Verifies" + v1/v2/v3 all true
```

> **References**:
> - `references/working-build-script.md` — exact pipeline with troubleshooting table
> - `references/terminal-ui-patterns.md` — copy/paste, command history, UI patterns for no-AndroidX terminal apps

## No AndroidX

Use `android.app.Activity`, `android.app.Notification.Builder` — no Jetpack. Extending `AppCompatActivity` will fail without compiling AndroidX JARs manually.

## Deliverable Verification

Before delivering, verify the APK actually contains what you expect — especially after code changes:

```bash
# 1. Extract DEX and check strings
unzip -o build/hermes.apk classes.dex -d /tmp/apk-check
strings /tmp/apk-check/classes.dex | grep -E "install|curl|sh|sheLL" | grep -v "^L"
# Confirm: uses `sh` not `bash` — Android has no bash

# 2. Verify signing schemes
$BT/apksigner verify --verbose build/hermes.apk

# 3. Check targetSdkVersion is set (not 0)
$BT/aapt2 dump badging build/hermes.apk 2>/dev/null | grep -E "^package:|sdkVersion:|targetSdkVersion:"
```

## Delivery

```bash
cp build/hermes.apk /sdcard/Download/HermesAgent.apk
```

## Pitfalls

- **ALIGN BEFORE SIGNING**: Never sign an APK and then modify it. If you zipalign after signing, the v2/v3 signature blocks get corrupted. Correct order: aapt2 link → package DEX → zipalign → apksigner sign. Do NOT run zipalign after apksigner.
- **jarsigner is insufficient**: `jarsigner` only produces v1 (JAR) signatures. Android 11+ (API 30+) rejects APKs without v2/v3 APK Signature Scheme. Use `apksigner` instead — it's a Java JAR wrapper that runs natively on any architecture including ARM64.
- **apksigner runs natively on ARM64**: `apksigner` is a shell script that launches `apksigner.jar` via Java. It is NOT an ELF binary — do NOT wrap it with QEMU. Java runs natively on ARM64.
- Shell scripts (`d8`, `aapt`) must NOT go through QEMU — only ELF binaries.
- Resource IDs break silently if R.java isn't regenerated on every build.
- **targetSdkVersion defaults to 0 if not passed to aapt2 link**: The manifest's `android:versionCode` / `android:versionName` attributes are NOT enough — `aapt2 link` must receive `--min-sdk-version N --target-sdk-version N --version-code N --version-name "X.Y.Z"` flags explicitly. Without `--target-sdk-version`, the value defaults to 0 and the Play Console / device installer rejects with `INSTALL_FAILED_DEPRECATED_SDK_VERSION: App package must target at least SDK version 24, but found 0`.
- APK bundles NO Python — Hermes is bootstrapped on first run via the official install script: `curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | sh` (not pip). Note: use `sh`, NOT `bash` — Android/Termux doesn't have bash by default.
- **`bash` is not available on Android/Termux**. Default shell is `sh`. Any `Runtime.exec` or script that pipes to `| bash` will fail with `sh: bash: inaccessible or not found`. Always use `sh` or `/system/bin/sh` in Android Java code.
