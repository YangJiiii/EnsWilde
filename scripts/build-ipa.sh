#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-Release}"
SCHEME="EnsWilde"
PROJECT="EnsWilde.xcodeproj"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/EnsWilde.xcarchive"
APP_NAME="EnsWilde"
IPA_PATH="$BUILD_DIR/${APP_NAME}.ipa"

echo "==> Building $APP_NAME ($CONFIG)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# =============================================================================
# BUILD AIRLIFT TỪ SOURCE CODE TRONG REPO
# =============================================================================
echo "==> Building AirliftFFI from local source in AirCardCore..."

if ! rustup target list --installed | grep -q "aarch64-apple-ios"; then
  rustup target add aarch64-apple-ios
fi

cd AirCardCore
cargo build --release --target aarch64-apple-ios
cd ..

# Tạo framework bundle chuẩn
FRAMEWORK_DIR="Frameworks/AirliftFFI.framework"
rm -rf "$FRAMEWORK_DIR"
mkdir -p "$FRAMEWORK_DIR/Headers"
mkdir -p "$FRAMEWORK_DIR/Modules"

# Copy binary và headers
cp AirCardCore/target/aarch64-apple-ios/release/libairlift_ffi.a "$FRAMEWORK_DIR/AirliftFFI"

AIRLIFT_H=$(find AirCardCore -name "airlift.h" | head -n 1)
GRAPPA_H=$(find AirCardCore -name "GrappaHelper.h" | head -n 1)

[ -n "$AIRLIFT_H" ] && cp "$AIRLIFT_H" "$FRAMEWORK_DIR/Headers/airlift.h"
[ -n "$GRAPPA_H" ] && cp "$GRAPPA_H" "$FRAMEWORK_DIR/Headers/GrappaHelper.h"

# Tạo modulemap và Info.plist
cat > "$FRAMEWORK_DIR/Modules/module.modulemap" <<EOF
framework module AirliftFFI {
    umbrella header "airlift.h"
    export *
    module * { export * }
}
EOF

cat > "$FRAMEWORK_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AirliftFFI</string>
    <key>CFBundleIdentifier</key>
    <string>com.enswilde.AirliftFFI</string>
    <key>CFBundleName</key>
    <string>AirliftFFI</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
EOF

echo "✅ Built AirliftFFI framework!"

# =============================================================================
# INJECT VÀO XCODE
# =============================================================================
echo "==> Injecting AirliftFFI & GrappaHelper into Xcode project..."
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project_path = "EnsWilde.xcodeproj"
  framework_path = "Frameworks/AirliftFFI.framework"
  
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == "EnsWilde" }
  
  unless target.nil?
    # Add framework
    file_ref = project.new_file(framework_path)
    target.frameworks_build_phase.add_file_reference(file_ref)
    
    embed_phase = target.copy_files_build_phases.find { |p| p.name == "Embed Frameworks" } 
    if embed_phase.nil?
      embed_phase = target.new_copy_files_build_phase("Embed Frameworks")
      embed_phase.dst_subfolder_spec = "10"
    end
    build_file = embed_phase.add_file_reference(file_ref)
    build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
    
    # Add GrappaHelper.m to compile sources
    grappa_m_path = Dir.glob("**/GrappaHelper.m").first
    if grappa_m_path
      grappa_ref = project.new_file(grappa_m_path)
      target.add_file_references([grappa_ref])
    end

    target.build_configurations.each do |config|
      config.build_settings["FRAMEWORK_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["FRAMEWORK_SEARCH_PATHS"] << "$(PROJECT_DIR)/Frameworks"
      config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]
      config.build_settings["OTHER_LDFLAGS"] << "-ObjC"
    end
    
    project.save
    puts "✅ Thành công: Đã nhúng AirliftFFI và GrappaHelper vào project!"
  else
    puts "❌ Lỗi: Không tìm thấy target EnsWilde"
    exit 1
  end
'

# =============================================================================
# ARCHIVE VÀ ĐÓNG GÓI IPA
# =============================================================================
XCB_ARGS=(
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -sdk iphoneos
  -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS"
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  CODE_SIGN_ENTITLEMENTS="" EXPANDED_CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""
  PROVISIONING_PROFILE_SPECIFIER=""
)

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild archive "${XCB_ARGS[@]}" | xcbeautify
else
  xcodebuild archive "${XCB_ARGS[@]}"
fi

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
APP_BASENAME="$(basename "$APP_PATH")"
rm -rf "$BUILD_DIR/Payload" && mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
rm -f  "$BUILD_DIR/Payload/${APP_BASENAME}/embedded.mobileprovision"

(cd "$BUILD_DIR" && zip -qry "$IPA_PATH" Payload)
echo "==> Done: $IPA_PATH"