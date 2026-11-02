#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-Release}"
SCHEME="EnsWilde"
PROJECT="EnsWilde.xcodeproj"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/EnsWilde.xcarchive"
APP_NAME="EnsWilde"
IPA_PATH="$BUILD_DIR/${APP_NAME}.ipa"

AIRCARD_LIB="Frameworks/ios-arm64/libairlift_ffi.a"
AIRCARD_HEADERS="Frameworks/ios-arm64/Headers"
GRAPPA_H="Sources/GrappaHelper.h" 
GRAPPA_M="Sources/GrappaHelper.m"
GRAPPA_DIR="$(dirname "$GRAPPA_H")"

echo "==> [1/4] Checking files..."
for f in "$AIRCARD_LIB" "$AIRCARD_HEADERS/airlift.h" "$GRAPPA_H" "$GRAPPA_M"; do
  if [ ! -f "$f" ]; then
    echo "❌ LỖI: Đéo tìm thấy $f. Push file .a lên Git LFS đi boss man."
    exit 1
  fi
done

echo "==> [2/4] Setting up build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> [3/4] Injecting Airlift.a + GrappaHelper.m..."
gem install xcodeproj --no-document >/dev/null 2>&1 || true
export AIRCARD_LIB AIRCARD_HEADERS GRAPPA_M GRAPPA_DIR

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.open("EnsWilde.xcodeproj")
  target = project.targets.find { |t| t.name == "EnsWilde" }
  exit 1 if target.nil?

  lib_path = ENV["AIRCARD_LIB"]
  grappa_m_path = ENV["GRAPPA_M"]
  grappa_dir = ENV["GRAPPA_DIR"]
  header_path = ENV["AIRCARD_HEADERS"]

  target.frameworks_build_phase.files_references.dup.each do |f|
    next unless f
    if f.path && f.path.end_with?("libairlift_ffi.a")
      target.frameworks_build_phase.remove_file_reference(f)
    end
  end

  target.source_build_phase.files_references.dup.each do |f|
    next unless f
    if f.path && f.path.end_with?("GrappaHelper.m")
      target.source_build_phase.remove_file_reference(f)
    end
  end

  lib_ref = project.files.find { |f| f.path == lib_path } || project.new_file(lib_path)
  target.frameworks_build_phase.add_file_reference(lib_ref)

  grappa_ref = project.files.find { |f| f.path == grappa_m_path } || project.new_file(grappa_m_path)
  target.source_build_phase.add_file_reference(grappa_ref)

  target.build_configurations.each do |config|
    h_paths = config.build_settings["HEADER_SEARCH_PATHS"] || ["$(inherited)"]
    h_paths << "$(PROJECT_DIR)/#{header_path}"
    h_paths << "$(PROJECT_DIR)/#{grappa_dir}"
    config.build_settings["HEADER_SEARCH_PATHS"] = h_paths.uniq

    lib_paths = config.build_settings["LIBRARY_SEARCH_PATHS"] || ["$(inherited)"]
    lib_paths << "$(PROJECT_DIR)/Frameworks/ios-arm64"
    config.build_settings["LIBRARY_SEARCH_PATHS"] = lib_paths.uniq
    
    ld_flags = config.build_settings["OTHER_LDFLAGS"] || ["$(inherited)"]
    ld_flags << "-ObjC"
    ld_flags << "-lairlift_ffi"
    config.build_settings["OTHER_LDFLAGS"] = ld_flags.uniq
    
    # Ép Xcode từ chối ký ở cấp độ Project
    config.build_settings["CODE_SIGNING_ALLOWED"] = "NO"
    config.build_settings["CODE_SIGNING_REQUIRED"] = "NO"
    config.build_settings["CODE_SIGN_IDENTITY"] = ""
    config.build_settings["CODE_SIGN_ENTITLEMENTS"] = ""
  end
  project.save
'

echo "==> [4/4] Archiving (Ép ra Unsigned)..."
XCB_ARGS=(
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -sdk iphoneos
  -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS"
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  CODE_SIGN_ENTITLEMENTS="" EXPANDED_CODE_SIGN_IDENTITY=""
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
)

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild archive "${XCB_ARGS[@]}" | xcbeautify
else
  xcodebuild archive "${XCB_ARGS[@]}"
fi

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "❌ LỖI: Đéo tìm thấy file .app sau khi archive!" >&2
  exit 1
fi

APP_BASENAME="$(basename "$APP_PATH")"
rm -rf "$BUILD_DIR/Payload" && mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"

echo "==> [Stripping] Cạo sạch chữ ký để đảm bảo Unsigned..."
# Xóa chữ ký của app chính
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
rm -f  "$BUILD_DIR/Payload/${APP_BASENAME}/embedded.mobileprovision"
codesign --remove-signature "$BUILD_DIR/Payload/${APP_BASENAME}/${APP_NAME}" 2>/dev/null || true

# Xóa chữ ký của toàn bộ Framework nhúng (nếu có)
if [ -d "$BUILD_DIR/Payload/${APP_BASENAME}/Frameworks" ]; then
    find "$BUILD_DIR/Payload/${APP_BASENAME}/Frameworks" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$BUILD_DIR/Payload/${APP_BASENAME}/Frameworks" -name "embedded.mobileprovision" -delete 2>/dev/null || true
    find "$BUILD_DIR/Payload/${APP_BASENAME}/Frameworks" -type f -perm +111 -exec codesign --remove-signature {} \; 2>/dev/null || true
fi

(cd "$BUILD_DIR" && zip -qry "$IPA_PATH" Payload)
echo "✅ DONE: $IPA_PATH (UNSIGNED 100%)"