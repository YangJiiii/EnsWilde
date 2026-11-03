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
# TỰ ĐỘNG DÒ TÌM STATIC LIB VÀ HEADERS (Bám sát cấu trúc thực tế)
# =============================================================================
echo "==> Locating libairlift_ffi.a and headers..."

# Tìm file .a ở bất kỳ đâu trong folder Frameworks (hoặc toàn repo)
LIB_PATH=$(find . -name "libairlift_ffi.a" -not -path "*/target/*" | head -n 1)
if [ -z "$LIB_PATH" ]; then
    echo "❌ Đ*o tìm thấy libairlift_ffi.a đâu cả. Boss man xem lại xem file build sẵn để đâu rồi?"
    exit 1
fi
LIB_DIR=$(dirname "$LIB_PATH")
echo "✅ Found lib: $LIB_PATH"

# Tìm folder chứa airlift.h
HEADER_FILE=$(find "$LIB_DIR" -name "airlift.h" | head -n 1)
if [ -z "$HEADER_FILE" ]; then
    # Nếu không thấy trong folder lib, tìm toàn repo
    HEADER_FILE=$(find . -name "airlift.h" -not -path "*/target/*" | head -n 1)
fi

if [ -z "$HEADER_FILE" ]; then
    echo "❌ Đ*o tìm thấy airlift.h. Thiếu header thì build bằng niềm tin à?"
    exit 1
fi
HEADER_DIR=$(dirname "$HEADER_FILE")
echo "✅ Found headers: $HEADER_DIR"

# Export biến môi trường để Ruby đọc được
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
    # 1. Add static lib (.a) vào Link Binary With Libraries
    # Dùng path tuyệt đối để tránh lỗi Xcode không tìm thấy
    abs_lib_path = File.expand_path(lib_path)
    lib_ref = project.new_file(abs_lib_path)
    target.frameworks_build_phase.add_file_reference(lib_ref)
    puts "✅ Đã link: #{lib_path}"
    
    # 2. Tìm và add GrappaHelper.m vào Compile Sources
    grappa_m_path = Dir.glob("**/GrappaHelper.m").first
    if grappa_m_path
      abs_grappa_path = File.expand_path(grappa_m_path)
      unless project.files.any? { |f| f.path == abs_grappa_path || f.path == grappa_m_path }
        grappa_ref = project.new_file(abs_grappa_path)
        target.add_file_references([grappa_ref])
        puts "✅ Đã add GrappaHelper.m vào Compile Sources"
      end
    else
      puts "⚠️ CẢNH BÁO: Đ*o tìm thấy file GrappaHelper.m trong repo!"
    end

    # 3. Cấu hình Build Settings
    abs_lib_dir = File.expand_path(lib_dir)
    abs_header_dir = File.expand_path(header_dir)
    
    target.build_configurations.each do |config|
      config.build_settings["LIBRARY_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["LIBRARY_SEARCH_PATHS"] << abs_lib_dir
      
      config.build_settings["HEADER_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["HEADER_SEARCH_PATHS"] << abs_header_dir
      
      config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]
      # Lấy tên file bỏ chữ "lib" và đuôi ".a" (ví dụ: libairlift_ffi.a -> -lairlift_ffi)
      lib_name = File.basename(lib_path).gsub(/^lib/, "").gsub(/\.a$/, "")
      config.build_settings["OTHER_LDFLAGS"] << "-l#{lib_name}"
      config.build_settings["OTHER_LDFLAGS"] << "-ObjC"
    end
    
    project.save
    puts "✅ Xong! Đã cấu hình Xcode project thành công."
  else
    puts "❌ Lỗi: Đ*o tìm thấy target EnsWilde trong project."
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