#!/bin/bash
set -e

APP_NAME="ZenbuShot"
BUILD_DIR=".build/app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BINARY="$MACOS/$APP_NAME"

# Create bundle structure
mkdir -p "$MACOS" "$RESOURCES"

# Copy localization resources
for lproj in CleanShotClone/Resources/*.lproj; do
    lang=$(basename "$lproj")
    mkdir -p "$RESOURCES/$lang"
    cp -f "$lproj"/*.strings "$RESOURCES/$lang/" 2>/dev/null || true
done

# Find all Swift files
SWIFT_FILES=$(find CleanShotClone -name "*.swift" | sort)

# Compile to a temp location first
TEMP_BINARY="/tmp/anyshot_build_$$"

echo "Compiling..."
swiftc \
    -o "$TEMP_BINARY" \
    -target arm64-apple-macosx13.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework AppKit \
    -framework ScreenCaptureKit \
    -framework Vision \
    -framework CoreImage \
    -framework Carbon \
    -framework AVFoundation \
    -framework CoreMedia \
    -framework ServiceManagement \
    $SWIFT_FILES

# Check if binary actually changed
NEEDS_SIGN=false
if [ -f "$BINARY" ]; then
    OLD_HASH=$(shasum -a 256 "$BINARY" | cut -d' ' -f1)
    NEW_HASH=$(shasum -a 256 "$TEMP_BINARY" | cut -d' ' -f1)
    if [ "$OLD_HASH" != "$NEW_HASH" ]; then
        echo "Binary changed, updating..."
        cp "$TEMP_BINARY" "$BINARY"
        NEEDS_SIGN=true
    else
        echo "Binary unchanged, skipping re-sign (permissions preserved)."
    fi
else
    echo "First build, creating app bundle..."
    cp "$TEMP_BINARY" "$BINARY"
    NEEDS_SIGN=true
fi

rm -f "$TEMP_BINARY"

# Write Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ZenbuShot</string>
    <key>CFBundleIdentifier</key>
    <string>com.zenbu.zenbushot</string>
    <key>CFBundleName</key>
    <string>ZenbuShot</string>
    <key>CFBundleDisplayName</key>
    <string>ZenbuShot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>ZenbuShot needs screen recording permission to capture screenshots.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>ZenbuShot needs accessibility permission for global keyboard shortcuts.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>ZenbuShot needs microphone access for screen recording with audio.</string>
    <key>NSCameraUsageDescription</key>
    <string>ZenbuShot needs camera access for webcam overlay during recordings.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Sign with hardened runtime + entitlements (required for TCC microphone/camera access)
ENTITLEMENTS="$(dirname "$0")/ZenbuShot.entitlements"
echo "Signing with hardened runtime + entitlements..."
codesign --force --deep --sign "36F0B6705A9F3FF9BA39E6AC4603258A7965EA02" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE" 2>&1 || {
    echo "Warning: ZenbuShot Developer signing failed, trying Developer ID..."
    codesign --force --deep --sign "Developer ID Application: Hao Hsu (V6ZDDG5Z68)" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        "$APP_BUNDLE" 2>&1 || {
        echo "Warning: All signing failed, falling back to ad-hoc with entitlements"
        codesign --force --deep --sign - \
            --options runtime \
            --entitlements "$ENTITLEMENTS" \
            "$APP_BUNDLE" 2>/dev/null
    }
}

# Deploy to /Applications
echo "Deploying to /Applications..."
pkill -f "ZenbuShot" 2>/dev/null || true
sleep 1
rm -rf /Applications/ZenbuShot.app
cp -R "$APP_BUNDLE" /Applications/ZenbuShot.app
# Verify deployment
if [ "$(shasum "$APP_BUNDLE/Contents/MacOS/ZenbuShot" | cut -d' ' -f1)" = "$(shasum /Applications/ZenbuShot.app/Contents/MacOS/ZenbuShot | cut -d' ' -f1)" ]; then
    echo "Deploy verified OK"
else
    echo "WARNING: Deploy mismatch, retrying..."
    sleep 1
    rm -rf /Applications/ZenbuShot.app
    cp -R "$APP_BUNDLE" /Applications/ZenbuShot.app
fi

xattr -dr com.apple.quarantine /Applications/ZenbuShot.app 2>/dev/null || true

# Verify entitlements are embedded
echo ""
echo "Verifying entitlements..."
codesign -d --entitlements - /Applications/ZenbuShot.app 2>&1 | grep -q "audio-input" && \
    echo "  ✓ audio-input entitlement present" || \
    echo "  ✗ WARNING: audio-input entitlement MISSING"
codesign -d --entitlements - /Applications/ZenbuShot.app 2>&1 | grep -q "camera" && \
    echo "  ✓ camera entitlement present" || \
    echo "  ✗ WARNING: camera entitlement MISSING"

# Reset TCC for fresh permission prompts (signature changed)
tccutil reset Microphone com.zenbu.zenbushot 2>/dev/null || true
tccutil reset Camera com.zenbu.zenbushot 2>/dev/null || true

echo ""
echo "Build complete. Deployed to /Applications/ZenbuShot.app"
echo "Run with: bash run.sh"
