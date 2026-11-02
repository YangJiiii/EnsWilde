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
# CẤU HÌNH ĐƯỜNG DẪN
# =============================================================================
AIRCARD_LIB="Frameworks/ios-arm64/libairlift_ffi.a"
AIRCARD_HEADERS="Frameworks/ios-arm64/Headers"

# Sửa lại nếu Grappa của mày nằm ở chỗ khác
GRAPPA_H="Sources/GrappaHelper.h" 
GRAPPA_M="Sources/GrappaHelper.m"
GRAPPA_DIR="$(dirname "$GRAPPA_H")"

echo "==> [1/4] Checking files..."
for f in "$AIRCARD_LIB" "$AIRCARD_HEADERS/airlift.h" "$GRAPPA_H" "$GRAPPA_M"; do
  if [ ! -f "$f" ]; then
    echo "❌ LỖI CHÍ MẠNG: Đéo tìm thấy $f"
    echo "Mày phải để file đúng chỗ như trong script chỉ định."
    exit 1
  fi
done

echo "==> [2/4] Setting up build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# =============================================================================
# INJECT VÀO XCODE BẰNG RUBY (ĐÃ FIX LỖI NIL)
# =============================================================================
echo "==> [3/4] Injecting Airlift.a + GrappaHelper.m into Xcode project..."
gem install xcodeproj --no-document >/dev/null 2>&1 || true

export AIRCARD_LIB AIRCARD_HEADERS GRAPPA_M GRAPPA_DIR

ruby -e '
  require "xcodeproj"
  project_path = "EnsWilde.xcodeproj"
  
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == "EnsWilde" }
  exit 1 if target.nil?

  lib_path = ENV["AIRCARD_LIB"]
  grappa_m_path = ENV["GRAPPA_M"]
  grappa_dir = ENV["GRAPPA_DIR"]
  header_path = ENV["AIRCARD_HEADERS"]

  # 1. Dọn dẹp file .a cũ trong Frameworks Phase (tránh lỗi nil path)
  target.frameworks_build_phase.files_references.dup.each do |f|
    next unless f # Bỏ qua nếu f bị nil
    if f.path && f.path.end_with?("libairlift_ffi.a")
      target.frameworks_build_phase.remove_file_reference(f)
    end
  end

  # 2. Dọn dẹp GrappaHelper.m cũ trong Compile Sources (tránh lỗi Duplicate)
  target.source_build_phase.files_references.dup.each do |f|
    next unless f # Bỏ qua nếu f bị nil
    if f.path && f.path.end_with?("GrappaHelper.m")
      target.source_build_phase.remove_file_reference(f)
    end
  end

  # 3. Add lại file .a và GrappaHelper.m
  lib_ref = project.files.find { |f| f.path == lib_path }
  lib_ref ||= project.new_file(lib_path)
  target.frameworks_build_phase.add_file_reference(lib_ref)

  grappa_ref = project.files.find { |f| f.path == grappa_m_path }
  grappa_ref ||= project.new_file(grappa_m_path)
  target.source_build_phase.add_file_reference(grappa_ref)

  # 4. Update Build Settings
  target.build_configurations.each do |config|
    # Header Search Paths
    h_paths = config.build_settings["HEADER_SEARCH_PATHS"] || ["$(inherited)"]
    h_paths << "$(PROJECT_DIR)/#{header_path}"
    h_paths << "$(PROJECT_DIR)/#{grappa_dir}"
    config.build_settings["HEADER_SEARCH_PATHS"] = h_paths.uniq

    # Library Search Paths (Quan trọng để fix lỗi linker)
    lib_paths = config.build_settings["LIBRARY_SEARCH_PATHS"] || ["$(inherited)"]
    lib_paths << "$(PROJECT_DIR)/Frameworks/ios-arm64"
    config.build_settings["LIBRARY_SEARCH_PATHS"] = lib_paths.uniq
    
    # Other Linker Flags
    ld_flags = config.build_settings["OTHER_LDFLAGS"] || ["$(inherited)"]
    ld_flags << "-ObjC"
    ld_flags << "-lairlift_ffi"
    config.build_settings["OTHER_LDFLAGS"] = ld_flags.uniq
  end

  project.save
  puts "✅ Xong phần inject!"
'

# =============================================================================
# ARCHIVE VÀ ĐÓNG GÓI IPA
# =============================================================================
echo "==> [4/4] Archiving and Packaging..."
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
  echo "❌ LỖI: Đéo tìm thấy file .app sau khi archive!" >&2
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

echo "============================================================"
echo "✅ DONE: $IPA_PATH"
echo "============================================================"