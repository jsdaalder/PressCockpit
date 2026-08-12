#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PRODUCT_NAME="JournalismWorkflowHub"
RESOURCE_BUNDLE_NAME="JournalismWorkflowHub_JournalismWorkflowHub.bundle"
APP_NAME="PressCockpit"
BUNDLE_ID="com.jsdaalder.presscockpit"
VERSION="0.2.0"
BUILD_NUMBER="1"
DEFAULT_PROFILE="standalone"
OUTPUT_DIR="$ROOT_DIR/dist"
DEFAULT_TEMP_ROOT="${TMPDIR:-/tmp}"
DEFAULT_TEMP_ROOT="${DEFAULT_TEMP_ROOT%/}"
SCRATCH_PATH="$DEFAULT_TEMP_ROOT/presscockpit-swiftpm-build"

usage() {
  cat <<'EOF'
Usage: scripts/build-macos-release.sh [options]

Options:
  --app-name NAME        App bundle name. Default: PressCockpit
  --bundle-id ID         macOS bundle identifier. Default: com.jsdaalder.presscockpit
  --version VERSION      Human-readable version. Default: 0.2.0
  --build-number NUMBER  Bundle build number. Default: 1
  --profile PROFILE      Default app profile at launch: standalone or standard. Default: standalone
  --output-dir PATH      Output directory for packaged artifacts. Default: dist
  --scratch-path PATH    Isolated SwiftPM scratch/build directory. Default: /tmp/presscockpit-swiftpm-build
  --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --profile)
      DEFAULT_PROFILE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --scratch-path)
      SCRATCH_PATH="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$DEFAULT_PROFILE" != "standalone" && "$DEFAULT_PROFILE" != "standard" ]]; then
  echo "Invalid profile: $DEFAULT_PROFILE. Expected 'standalone' or 'standard'." >&2
  exit 1
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$SCRATCH_PATH"
mkdir -p "$SCRATCH_PATH"

CACHE_HOME="$SCRATCH_PATH/home"
MODULE_CACHE_PATH="$SCRATCH_PATH/module-cache"
TEMP_PATH="$SCRATCH_PATH/tmp"

mkdir -p "$CACHE_HOME" "$MODULE_CACHE_PATH" "$TEMP_PATH"

export HOME="$CACHE_HOME"
export XDG_CACHE_HOME="$CACHE_HOME/.cache"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE_PATH"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH"
export TMPDIR="$TEMP_PATH/"

swift build --scratch-path "$SCRATCH_PATH" -c release

BIN_PATH="$SCRATCH_PATH/release"
EXECUTABLE_PATH="$BIN_PATH/$PRODUCT_NAME"
RESOURCE_BUNDLE_PATH="$BIN_PATH/$RESOURCE_BUNDLE_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Missing compiled executable: $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE_PATH" >&2
  exit 1
fi

STAGING_DIR="$OUTPUT_DIR/$APP_NAME-staging"
APP_PATH="$STAGING_DIR/$APP_NAME.app"
DIST_APP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.app"
LEGACY_DIST_APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-macOS-$VERSION.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"

rm -rf "$STAGING_DIR" "$DIST_APP_PATH" "$LEGACY_DIST_APP_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"
mkdir -p "$MACOS_PATH" "$RESOURCES_PATH"

cp "$EXECUTABLE_PATH" "$MACOS_PATH/$PRODUCT_NAME"
cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_PATH/$RESOURCE_BUNDLE_NAME"
ln -s "Contents/Resources/$RESOURCE_BUNDLE_NAME" "$APP_PATH/$RESOURCE_BUNDLE_NAME"

cat > "$CONTENTS_PATH/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSRequiresNativeExecution</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSEnvironment</key>
  <dict>
    <key>JWH_APP_PROFILE</key>
    <string>$DEFAULT_PROFILE</string>
  </dict>
</dict>
</plist>
EOF

find "$APP_PATH" -name '.DS_Store' -delete
xattr -cr "$APP_PATH"
ditto "$APP_PATH" "$DIST_APP_PATH"
xattr -cr "$DIST_APP_PATH"

(
  cd "$STAGING_DIR"
  COPYFILE_DISABLE=1 zip -qry -y "$ZIP_PATH" "$APP_NAME.app"
)
shasum -a 256 "$ZIP_PATH" > "$CHECKSUM_PATH"

echo "Created:"
echo "  $DIST_APP_PATH"
echo "  $ZIP_PATH"
echo "  $CHECKSUM_PATH"
