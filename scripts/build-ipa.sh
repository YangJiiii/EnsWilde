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

# TÌM ĐÚNG FILE DEVICE
LIB_PATH=$(find ./Frameworks/ios-arm64 -name "libairlift_ffi.a" 2>/dev/null | head -n 1)
if [ -z "$LIB_PATH" ]; then echo "❌ Đ*o tìm thấy libairlift_ffi.a"; exit 1; fi
LIB_DIR=$(dirname "$LIB_PATH")

HEADER_FILE=$(find "$LIB_DIR" -name "airlift.h" | head -n 1)
if [ -z "$HEADER_FILE" ]; then echo "❌ Đ*o tìm thấy airlift.h"; exit 1; fi
HEADER_DIR=$(dirname "$HEADER_FILE")

export LIB_PATH
export LIB_DIR
export HEADER_DIR

# INJECT VÀO XCODE
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.open("EnsWilde.xcodeproj")
  target = project.targets.find { |t| t.name == "EnsWilde" }
  
  unless target.nil?
    abs_lib_path = File.expand_path(ENV["LIB_PATH"])
    lib_ref = project.new_file(abs_lib_path)
    target.frameworks_build_phase.add_file_reference(lib_ref)
    
    grappa_m_path = Dir.glob("**/GrappaHelper.m").first
    if grappa_m_path
      abs_grappa_path = File.expand_path(grappa_m_path)
      already_in_build = target.source_build_phase.files.any? do |f| 
        f.file_ref && f.file_ref.path && (f.file_ref.path.include?("GrappaHelper.m") || File.expand_path(f.file_ref.path) == abs_grappa_path)
      end
      if !already_in_build
        file_ref = project.files.find { |f| f.path && f.path.include?("GrappaHelper.m") } || project.new_file(abs_grappa_path)
        target.add_file_references([file_ref])
      end
    end

    target.build_configurations.each do |config|
      config.build_settings["LIBRARY_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["LIBRARY_SEARCH_PATHS"] << File.expand_path(ENV["LIB_DIR"])
      config.build_settings["HEADER_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["HEADER_SEARCH_PATHS"] << File.expand_path(ENV["HEADER_DIR"])
      
      config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]
      lib_name = File.basename(ENV["LIB_PATH"]).gsub(/^lib/, "").gsub(/\.a$/, "")
      
      # FIX: Ép export động và giữ lại symbol cụ thể
      config.build_settings["OTHER_LDFLAGS"] << "-l#{lib_name}"
      config.build_settings["OTHER_LDFLAGS"] << "-ObjC"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-export_dynamic"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-exported_symbol,_ALGetGrappaToken"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-force_load,\"#{abs_lib_path}\""
    end
    project.save
  end
'

# ARCHIVE
XCB_ARGS=(
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -sdk iphoneos
  -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS"
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
)

xcodebuild archive "${XCB_ARGS[@]}" | xcbeautify || xcodebuild archive "${XCB_ARGS[@]}"

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
APP_BASENAME="$(basename "$APP_PATH")"
rm -rf "$BUILD_DIR/Payload" && mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
(cd "$BUILD_DIR" && zip -qry "$IPA_PATH" Payload)