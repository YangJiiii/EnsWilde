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
# TÌM ĐÚNG FILE DEVICE (Bỏ qua simulator)
# =============================================================================
echo "==> Locating libairlift_ffi.a (Device ARM64) and headers..."

LIB_PATH=$(find ./Frameworks/ios-arm64 -name "libairlift_ffi.a" 2>/dev/null | head -n 1)
if [ -z "$LIB_PATH" ]; then
    echo "❌ Đ*o tìm thấy libairlift_ffi.a cho DEVICE trong ./Frameworks/ios-arm64/"
    exit 1
fi
LIB_DIR=$(dirname "$LIB_PATH")
echo "✅ Found device lib: $LIB_PATH"

HEADER_FILE=$(find "$LIB_DIR" -name "airlift.h" | head -n 1)
if [ -z "$HEADER_FILE" ]; then
    echo "❌ Đ*o tìm thấy airlift.h."
    exit 1
fi
HEADER_DIR=$(dirname "$HEADER_FILE")
echo "✅ Found headers: $HEADER_DIR"

export LIB_PATH
export LIB_DIR
export HEADER_DIR

# =============================================================================
# INJECT VÀO XCODE BẰNG RUBY
# =============================================================================
echo "==> Injecting Airlift Static Lib & GrappaHelper vào Xcode project..."
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project_path = "EnsWilde.xcodeproj"
  
  lib_path = ENV["LIB_PATH"]
  lib_dir = ENV["LIB_DIR"]
  header_dir = ENV["HEADER_DIR"]
  
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == "EnsWilde" }
  
  unless target.nil?
    abs_lib_path = File.expand_path(lib_path)
    lib_ref = project.new_file(abs_lib_path)
    target.frameworks_build_phase.add_file_reference(lib_ref)
    
    # Tìm GrappaHelper.m và check duplicate
    grappa_m_path = Dir.glob("**/GrappaHelper.m").first
    if grappa_m_path
      abs_grappa_path = File.expand_path(grappa_m_path)
      
      already_in_build = target.source_build_phase.files.any? do |f| 
        f.file_ref && f.file_ref.path && (f.file_ref.path.include?("GrappaHelper.m") || File.expand_path(f.file_ref.path) == abs_grappa_path)
      end

      if !already_in_build
        file_ref = project.files.find { |f| f.path && f.path.include?("GrappaHelper.m") }
        file_ref ||= project.new_file(abs_grappa_path)
        target.add_file_references([file_ref])
        puts "✅ Đã add GrappaHelper.m vào Compile Sources"
      else
        puts "✅ GrappaHelper.m đã có sẵn trong Compile Sources, bỏ qua."
      end
    end

    target.build_configurations.each do |config|
      config.build_settings["LIBRARY_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["LIBRARY_SEARCH_PATHS"] << File.expand_path(lib_dir)
      
      config.build_settings["HEADER_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["HEADER_SEARCH_PATHS"] << File.expand_path(header_dir)
      
      config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]
      lib_name = File.basename(lib_path).gsub(/^lib/, "").gsub(/\.a$/, "")
      
      # FIX QUAN TRỌNG: Ép export symbol ALGetGrappaToken ra để Rust core gọi dlsym
      config.build_settings["OTHER_LDFLAGS"] << "-l#{lib_name}"
      config.build_settings["OTHER_LDFLAGS"] << "-ObjC"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-exported_symbol,_ALGetGrappaToken"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-exported_symbol,_ALGetGrappaToken" # Thêm 2 lần cho chắc (đ*o đùa được với thằng Linker)
    end
    
    project.save
    puts "✅ Xong! Đã cấu hình Xcode project (có export Grappa symbol)."
  else
    puts "❌ Lỗi: Đ*o tìm thấy target EnsWilde."
    exit 1
  end
'

# =============================================================================
# ARCHIVE VÀ ĐÓNG GÓI IPA
# =============================================================================
echo "==> Archiving..."
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

echo "==> Đóng gói IPA..."
APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
APP_BASENAME="$(basename "$APP_PATH")"
rm -rf "$BUILD_DIR/Payload" && mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
rm -f  "$BUILD_DIR/Payload/${APP_BASENAME}/embedded.mobileprovision"

(cd "$BUILD_DIR" && zip -qry "$IPA_PATH" Payload)
echo "🔥 Done: $IPA_PATH"