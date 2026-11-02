#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-Release}"
SCHEME="EnsWilde"
PROJECT="EnsWilde.xcodeproj"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/EnsWilde.xcarchive"
APP_NAME="EnsWilde"
IPA_PATH="$BUILD_DIR/${APP_NAME}.ipa"

# =============================================================================
# ĐƯỜNG DẪN TỚI FILE MÀY ĐÃ NÉM VÔ
# =============================================================================
# Dựa theo ảnh, mày đang có cấu trúc XCFramework:
# Frameworks/ios-arm64/libairlift_ffi.a
# Frameworks/ios-arm64/Headers/airlift.h
AIRCARD_LIB="Frameworks/ios-arm64/libairlift_ffi.a"
AIRCARD_HEADERS="Frameworks/ios-arm64/Headers"

# Mày để GrappaHelper.h/.m ở đâu thì sửa lại 2 dòng này:
GRAPPA_H="GrappaHelper/GrappaHelper.h"
GRAPPA_M="GrappaHelper/GrappaHelper.m"

echo "==> Checking files..."
for f in "$AIRCARD_LIB" "$AIRCARD_HEADERS/airlift.h" "$GRAPPA_H" "$GRAPPA_M"; do
  if [ ! -f "$f" ]; then
    echo "❌ LỖI: Đéo tìm thấy $f"
    echo "Mày phải để file đúng chỗ như trong script chỉ định."
    exit 1
  fi
done

echo "==> Building $APP_NAME ($CONFIG)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# =============================================================================
# INJECT VÀO XCODE BẰNG RUBY
# =============================================================================
echo "==> Injecting Airlift.a + GrappaHelper.m into Xcode project..."
gem install xcodeproj --no-document >/dev/null
ruby -e '
  require "xcodeproj"
  project_path = "EnsWilde.xcodeproj"
  
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == "EnsWilde" }
  exit 1 if target.nil?

  # 1. Add thư viện Rust (.a) vào Link Binary With Libraries
  lib_path = "Frameworks/ios-arm64/libairlift_ffi.a"
  lib_ref = project.new_file(lib_path)
  target.frameworks_build_phase.add_file_reference(lib_ref)

  # 2. Add GrappaHelper.m vào Compile Sources
  grappa_m_path = "GrappaHelper/GrappaHelper.m"
  # Check nếu file đã có trong project chưa để tránh add trùng
  existing_file = project.files.find { |f| f.path == grappa_m_path }
  if existing_file.nil?
    file_ref = project.new_file(grappa_m_path)
    target.add_file_references([file_ref])
  end

  # 3. Set Header Search Paths
  target.build_configurations.each do |config|
    paths = config.build_settings["HEADER_SEARCH_PATHS"] || ["$(inherited)"]
    paths << "$(PROJECT_DIR)/Frameworks/ios-arm64/Headers"
    paths << "$(PROJECT_DIR)/GrappaHelper"
    config.build_settings["HEADER_SEARCH_PATHS"] = paths.uniq
  end

  project.save
  puts "✅ Đã inject xong!"
'

# =============================================================================
# ARCHIVE VÀ ĐÓNG GÓI IPA
# =============================================================================
echo "==> Archiving..."
XCB_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -sdk iphoneos
  -archivePath "$ARCHIVE_PATH"
  -destination "generic/platform=iOS"
  CODE_SIGN_IDENTITY=""
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGN_ENTITLEMENTS=""
  EXPANDED_CODE_SIGN_IDENTITY=""
  DEVELOPMENT_TEAM=""
  PROVISIONING_PROFILE_SPECIFIER=""
)

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild archive "${XCB_ARGS[@]}" | xcbeautify
else
  xcodebuild archive "${XCB_ARGS[@]}"
fi

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "error: no .app found" >&2
  exit 1
fi

APP_BASENAME="$(basename "$APP_PATH")"
rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
rm -f  "$BUILD_DIR/Payload/${APP_BASENAME}/embedded.mobileprovision"

(
  cd "$BUILD_DIR"
  zip -qry "$IPA_PATH" Payload
)

echo "==> Done: $IPA_PATH"