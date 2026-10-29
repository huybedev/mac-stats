#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacStats"
APP_BUNDLE="${APP_NAME}.app"

# Minimum macOS version. MUST match LSMinimumSystemVersion in Info.plist.
# This gets baked into the binary's LC_BUILD_VERSION (minos), which is what
# Launch Services actually checks. Without an explicit -target, swiftc stamps
# minos to the *build machine's* OS version, so the app fails to launch on any
# older Mac with error -10825 (kLSIncompatibleSystemVersionErr).
DEPLOYMENT_TARGET="11.0"

echo "=== Building ${APP_NAME} (Optimized, Universal) ==="

# 1. Generate icon
echo "[1/4] Generating AppIcon.icns..."
python3 generate_icon.py || echo "Warning: Icon generation failed, continuing..."

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/macstats-build.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT
FAN_SHARED=(FanControl/Models.swift FanControl/Activity.swift FanControl/FanSMC.swift FanControl/Platform.swift)
SOURCES=(SMC.swift StatsEngine.swift StatusBarView.swift Updater.swift
    "${FAN_SHARED[@]}" FanControl/Localization.swift FanControl/AppModel.swift
    FanControl/Dashboard.swift FanControl/Feature.swift AppDelegate.swift main.swift)
COMMON_FLAGS=(-swift-version 5 -module-cache-path "$BUILD_DIR/modules" -Osize -wmo -module-name MacStats -Xlinker -dead_strip \
    -framework AppKit -framework IOKit -framework Foundation \
    -framework SwiftUI -Xlinker -weak_framework -Xlinker Charts -framework Security -framework ServiceManagement)

# 2. Compile a universal (arm64 + x86_64) Swift executable, pinning the
#    deployment target so it runs on macOS ${DEPLOYMENT_TARGET} and newer,
#    on both Apple Silicon and Intel Macs.
echo "[2/4] Compiling universal binary (arm64 + x86_64), min macOS ${DEPLOYMENT_TARGET}..."
swiftc "${COMMON_FLAGS[@]}" -target "arm64-apple-macosx${DEPLOYMENT_TARGET}" \
    "${SOURCES[@]}" -o "$BUILD_DIR/${APP_NAME}_arm64"
swiftc "${COMMON_FLAGS[@]}" -target "x86_64-apple-macosx${DEPLOYMENT_TARGET}" \
    "${SOURCES[@]}" -o "$BUILD_DIR/${APP_NAME}_x86_64"

lipo -create "$BUILD_DIR/${APP_NAME}_arm64" "$BUILD_DIR/${APP_NAME}_x86_64" -output "$BUILD_DIR/${APP_NAME}_bin"
rm -f "$BUILD_DIR/${APP_NAME}_arm64" "$BUILD_DIR/${APP_NAME}_x86_64"

# Strip debug symbols and local symbols to minimize binary
strip -x "$BUILD_DIR/${APP_NAME}_bin" || true

# 3. Create .app bundle structure
echo "[3/4] Packaging ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

mv "$BUILD_DIR/${APP_NAME}_bin" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/"
fi

# Fan control is optional on macOS 14+; the monitor keeps its macOS 11 target.
# A separate helper executable is the only process allowed to write fan settings.
HELPER_ID="com.openhoangnc.macstats.FanHelper"
HELPER="$APP_BUNDLE/Contents/Resources/MacStatsFanHelper"
for arch in arm64 x86_64; do
    swiftc -swift-version 5 -Osize -wmo -module-cache-path "$BUILD_DIR/modules" \
        -target "$arch-apple-macosx14.0" "${FAN_SHARED[@]}" \
        FanControl/Controller.swift FanControl/Helper.swift \
        -framework IOKit -framework Security -o "$BUILD_DIR/helper_$arch"
done
lipo -create "$BUILD_DIR/helper_arm64" "$BUILD_DIR/helper_x86_64" -output "$HELPER"
codesign --force --sign - --options runtime --identifier "$HELPER_ID" "$HELPER"
arm_hash=$(codesign -dv --arch arm64 --verbose=4 "$HELPER" 2>&1 | awk -F= '/^CDHash=/{print $2}')
intel_hash=$(codesign -dv --arch x86_64 --verbose=4 "$HELPER" 2>&1 | awk -F= '/^CDHash=/{print $2}')
[[ "$arm_hash" =~ ^[0-9a-f]{40}$ && "$intel_hash" =~ ^[0-9a-f]{40}$ ]]
printf 'identifier "%s" and (cdhash H"%s" or cdhash H"%s")\n' \
    "$HELPER_ID" "$arm_hash" "$intel_hash" > "$APP_BUNDLE/Contents/Resources/fan-helper-requirement.txt"
codesign --verify --all-architectures --strict -R "=$(cat "$APP_BUNDLE/Contents/Resources/fan-helper-requirement.txt")" "$HELPER"
cp FanControl/Resources/* "$APP_BUNDLE/Contents/Resources/"

# 4. Sign binary locally
echo "[4/4] Signing app bundle locally..."
codesign --force --sign - "${APP_BUNDLE}"
codesign --verify --deep --all-architectures --strict "${APP_BUNDLE}"

echo "=== Build Complete! ==="
echo "App created at: $(pwd)/${APP_BUNDLE}"
echo "Run with: open ${APP_BUNDLE}"
