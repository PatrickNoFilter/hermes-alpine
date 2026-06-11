# Working Hermes APK Build Script

This script was verified working on ARM64 PRoot (Termux) with QEMU-wrapped x86_64 SDK tools.

## Variables

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
export PATH=$JAVA_HOME/bin:$PATH
SDK=/opt/android-sdk
BT=$SDK/build-tools/34.0.0
PLATFORM=$SDK/platforms/android-34
QEMU=/usr/bin/qemu-x86_64
```

## QEMU Wrappers

Create wrappers for x86_64 ELF binaries in the SDK's build-tools directory. This lets manual builds AND any tooling that reads `$ANDROID_HOME/build-tools/` work transparently.

```bash
for bin in aapt2 zipalign; do
  mv "$BT/$bin" "$BT/$bin.bin"
  printf '#!/bin/bash\nexec /usr/bin/qemu-x86_64 %s.bin "$@"\n' "$BT/$bin" > "$BT/$bin"
  chmod +x "$BT/$bin"
done
```

Shell scripts (`d8`, `aapt`, `apksigner`) are NOT wrapped — they run natively via Java.

## Full Build Pipeline

\`\`\`bash
# Step 0: Clean
rm -rf build
mkdir -p build/{classes,dex,res-compiled,gen}

# Step 1: Compile XML resources
find app/src/main/res -type f -name "*.xml" | while read f; do
  $BT/aapt2 compile -o build/res-compiled/ "$f"
done

# Step 2: Link + generate R.java
# CRITICAL: --min-sdk-version, --target-sdk-version, --version-code, --version-name
# MUST be passed here. Manifest XML attributes alone are NOT enough — without
# --target-sdk-version, the value defaults to 0 and installation is rejected.
FLAT_FILES=$(find build/res-compiled -name "*.flat" | tr '\n' ' ')
$BT/aapt2 link -o build/unaligned.apk \\
  -I $PLATFORM/android.jar \\
  --manifest app/src/main/AndroidManifest.xml \\
  --java build/gen \\
  --min-sdk-version 24 \\
  --target-sdk-version 34 \\
  --version-code 1 \\
  --version-name "1.0.0" \\
  --auto-add-overlay $FLAT_FILES

# Step 3: Compile Java (no AndroidX)
javac -source 17 -target 17 \
  --system $JAVA_HOME \
  -classpath "$PLATFORM/android.jar:build/gen" \
  -d build/classes \
  app/src/main/java/com/hermes/agent/*.java

# Step 4: DEX
$BT/d8 --release --lib $PLATFORM/android.jar \\
  --min-api 24 --output build/dex \\
  $(find build/classes -name "*.class")

# Step 5: Package DEX
cp build/unaligned.apk build/unsigned.apk
(cd build/dex && zip -q ../unsigned.apk *.dex)

# Step 6: Align BEFORE signing (CRITICAL: align first, sign second)
$BT/zipalign -f -v 4 build/unsigned.apk build/aligned.apk

# Step 7: Sign with apksigner (v1 + v2 + v3)
# Generate keystore if needed
KS=debug.keystore
[ -f "$KS" ] || keytool -genkey -v -keystore "$KS" \
  -alias androiddebugkey -storepass android -keypass android \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"

$BT/apksigner sign \
  --ks "$KS" --ks-pass pass:android \
  --ks-key-alias androiddebugkey \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  --out build/hermes.apk \
  build/aligned.apk

# Step 8: Verify
$BT/apksigner verify --verbose build/hermes.apk
# Expect: "Verifies" + v1 / v2 / v3 all true
```

## Common Errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| "JAR signature indicates v2/v3 but no such signature found" | zipalign ran after apksigner | Build new, zipalign FIRST |
| "INSTALL_FAILED_DEPRECATED_SDK_VERSION: must target at least SDK 24, but found 0" | aapt2 link didn't receive --target-sdk-version | Add `--target-sdk-version 34` to aapt2 link (manifest attributes alone don't set this) |
| "INSTALL_FAILED_NO_MATCHING_ABIS" | APK contains native code for wrong arch | No native code should be embedded (pure Java) |
| "App not installed" on Android 11+ | v1-only JAR signature | Use apksigner (produces v2/v3) |
| Gradle daemon hangs/timeouts | JVM start overhead on ARM64 PRoot | Use manual pipeline above |
| `aapt2: Exec format error` | x86_64 binary on ARM64 without QEMU wrapper | Create QEMU wrapper as shown above |
