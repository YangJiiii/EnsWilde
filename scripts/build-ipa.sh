#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-Release}"
SCHEME="EnsWilde"
PROJECT="EnsWilde.xcodeproj"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/EnsWilde.xcarchive"
APP_NAME="EnsWilde"
IPA_PATH="$BUILD_DIR/${APP_NAME}.ipa"

echo "==> Bắt đầu build $APP_NAME ($CONFIG)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ==============================================================================
# FIX LỖI: Thêm || true để grep không làm sập script khi không tìm thấy
# Mở rộng tìm kiếm ra toàn bộ thư mục dự án (.) thay vì chỉ ./Frameworks
# ==============================================================================
echo "==> Đang tìm file thư viện (.a) và header (.h)..."
LIB_PATH=$(find . -name "*airlift*.a" 2>/dev/null | head -n 1 || true)
if [ -z "$LIB_PATH" ]; then 
  LIB_PATH=$(find . -name "*.a" 2>/dev/null | head -n 1 || true)
fi

if [ -z "$LIB_PATH" ]; then 
  echo "❌ LỖI: Đ*o tìm thấy file thư viện (.a) trong dự án."
  echo "Danh sách file hiện tại:"
  ls -la
  exit 1
fi
LIB_DIR=$(dirname "$LIB_PATH")
echo "✅ Tìm thấy Lib: $LIB_PATH"

HEADER_FILE=$(find . -name "airlift.h" 2>/dev/null | head -n 1 || true)
if [ -z "$HEADER_FILE" ]; then 
  echo "❌ LỖI: Đ*o tìm thấy airlift.h trong dự án."
  exit 1
fi
HEADER_DIR=$(dirname "$HEADER_FILE")
echo "✅ Tìm thấy Header: $HEADER_FILE"
# ==============================================================================

export LIB_PATH
export LIB_DIR
export HEADER_DIR

# Tạo file exported_symbols.txt để force export
EXPORT_SYMBOLS_FILE="$BUILD_DIR/exported_symbols.txt"
echo "_ALGetGrappaToken" > "$EXPORT_SYMBOLS_FILE"
export EXPORT_SYMBOLS_FILE

# INJECT VÀO XCODE BẰNG RUBY
echo "==> Đang cấu hình Xcode Project..."
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.open("EnsWilde.xcodeproj")
  target = project.targets.find { |t| t.name == "EnsWilde" }
  
  unless target.nil?
    abs_lib_path = File.expand_path(ENV["LIB_PATH"])
    
    # Thêm Lib file (nếu chưa có)
    unless target.frameworks_build_phase.files.any? { |f| f.file_ref && f.file_ref.path && f.file_ref.path.include?(File.basename(abs_lib_path)) }
      lib_ref = project.new_file(abs_lib_path)
      target.frameworks_build_phase.add_file_reference(lib_ref)
    end
    
    # Thêm GrappaHelper.m (nếu chưa có)
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
      
      # Set -fvisibility=default cho GrappaHelper.m
      target.source_build_phase.files.each do |build_file|
        if build_file.file_ref && build_file.file_ref.path && build_file.file_ref.path.include?("GrappaHelper.m")
          build_file.settings = { "COMPILER_FLAGS" => "-fvisibility=default" }
        end
      end
    end

    target.build_configurations.each do |config|
      config.build_settings["LIBRARY_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["LIBRARY_SEARCH_PATHS"] << File.expand_path(ENV["LIB_DIR"])
      config.build_settings["HEADER_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["HEADER_SEARCH_PATHS"] << File.expand_path(ENV["HEADER_DIR"])
      
      config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]
      lib_name = File.basename(ENV["LIB_PATH"]).gsub(/^lib/, "").gsub(/\.a$/, "")
      
      config.build_settings["OTHER_LDFLAGS"] << "-l#{lib_name}"
      config.build_settings["OTHER_LDFLAGS"] << "-ObjC"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-export_dynamic"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-exported_symbol,_ALGetGrappaToken"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-exported_symbols_list,\"#{ENV["EXPORT_SYMBOLS_FILE"]}\""
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-u,_ALGetGrappaToken"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-no_dead_strip_inits_and_terms"
      config.build_settings["OTHER_LDFLAGS"] << "-Wl,-force_load,\"#{abs_lib_path}\""
      
      config.build_settings["STRIP_INSTALLED_PRODUCT"] = "NO"
      config.build_settings["COPY_PHASE_STRIP"] = "NO"
      config.build_settings["DEAD_CODE_STRIPPING"] = "NO"
      config.build_settings["STRIP_STYLE"] = "non-global"
    end
    project.save
    puts "✅ Đã cấu hình build settings thành công"
  end
'

# ARCHIVE
echo "==> Bắt đầu Archive..."
XCB_ARGS=(
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -sdk iphoneos
  -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS"
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
)

# Bỏ xcbeautify để thấy log lỗi rõ hơn nếu có
xcodebuild archive "${XCB_ARGS[@]}"

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
if [ -z "$APP_PATH" ]; then
  echo "❌ LỖI: Không tìm thấy file .app sau khi archive"
  exit 1
fi

APP_BASENAME="$(basename "$APP_PATH")"
rm -rf "$BUILD_DIR/Payload" && mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
(cd "$BUILD_DIR" && zip -qry "$IPA_PATH" Payload)
echo "🔥 Done: $IPA_PATH"