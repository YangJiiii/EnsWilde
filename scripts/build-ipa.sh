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
# FIX LINKER: Chỉ chọn DEVICE slice (ios-arm64), loại bỏ simulator/x86_64
# ==============================================================================
echo "==> Đang tìm file thư viện (.a) DEVICE slice và header (.h)..."

LIB_PATH=$(find . -type f -name "*airlift*.a" \
  ! -path "*simulator*" ! -path "*x86_64*" 2>/dev/null | head -n 1 || true)

# Fallback: bất kỳ .a nào không phải simulator
if [ -z "$LIB_PATH" ]; then
  LIB_PATH=$(find . -type f -name "*.a" \
    ! -path "*simulator*" ! -path "*x86_64*" 2>/dev/null | head -n 1 || true)
fi

if [ -z "$LIB_PATH" ]; then
  echo "❌ LỖI: Không tìm thấy slice iOS-device (.a) nào (đã loại trừ simulator)."
  echo "Danh sách .a hiện có:"
  find . -name "*.a" 2>/dev/null || true
  echo ""
  echo "👉 Nếu chỉ có ios-arm64-simulator, bạn phải build lại lib cho DEVICE:"
  echo "   cargo build --release --target aarch64-apple-ios"
  echo "   xcodebuild -create-xcframework \\"
  echo "     -library ios-arm64/libairlift_ffi.a         -headers ios-arm64/Headers \\"
  echo "     -library ios-arm64-simulator/libairlift_ffi.a -headers ios-arm64-simulator/Headers \\"
  echo "     -output AirliftFFI.xcframework"
  exit 1
fi
LIB_DIR=$(dirname "$LIB_PATH")
echo "✅ Tìm thấy Lib (device): $LIB_PATH"

HEADER_FILE=$(find . -type f -name "airlift.h" \
  ! -path "*simulator*" ! -path "*x86_64*" 2>/dev/null | head -n 1 || true)

if [ -z "$HEADER_FILE" ]; then
  echo "❌ LỖI: Không tìm thấy airlift.h cho device slice."
  echo "Danh sách airlift.h hiện có:"
  find . -name "airlift.h" 2>/dev/null || true
  exit 1
fi
HEADER_DIR=$(dirname "$HEADER_FILE")
echo "✅ Tìm thấy Header (device): $HEADER_FILE"
# ==============================================================================

export LIB_PATH
export LIB_DIR
export HEADER_DIR

EXPORT_SYMBOLS_FILE="$BUILD_DIR/exported_symbols.txt"
echo "_ALGetGrappaToken" > "$EXPORT_SYMBOLS_FILE"
export EXPORT_SYMBOLS_FILE

echo "==> Đang cấu hình Xcode Project..."
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.open("EnsWilde.xcodeproj")
  target = project.targets.find { |t| t.name == "EnsWilde" }
  raise "❌ Không tìm thấy target EnsWilde" if target.nil?

  abs_lib_path = File.expand_path(ENV["LIB_PATH"])
  abs_lib_dir  = File.expand_path(ENV["LIB_DIR"])
  abs_hdr_dir  = File.expand_path(ENV["HEADER_DIR"])
  lib_name     = File.basename(abs_lib_path).gsub(/^lib/, "").gsub(/\.a$/, "")

  # ---- 1) Link file .a (device) ----
  unless target.frameworks_build_phase.files.any? { |f|
    f.file_ref && f.file_ref.path && f.file_ref.path.include?(File.basename(abs_lib_path))
  }
    lib_ref = project.new_file(abs_lib_path)
    target.frameworks_build_phase.add_file_reference(lib_ref)
  end

  # ---- 2) GrappaHelper.m: dedupe + set -fvisibility=default ----
  grappa_m_path = Dir.glob("**/GrappaHelper.m").first
  if grappa_m_path
    abs_grappa = File.expand_path(grappa_m_path)
    seen = false
    target.source_build_phase.files.dup.each do |bf|
      path = bf.file_ref && bf.file_ref.path
      next unless path && path.include?("GrappaHelper.m")
      if seen
        bf.remove_from_project
        puts "🧹 Đã xoá GrappaHelper.m trùng lặp khỏi build phase"
      else
        seen = true
        bf.settings = { "COMPILER_FLAGS" => "-fvisibility=default" }
      end
    end
    unless seen
      file_ref = project.files.find { |f| f.path && f.path.include?("GrappaHelper.m") } \
                 || project.new_file(abs_grappa)
      bf = target.source_build_phase.add_file_reference(file_ref, true)
      bf.settings = { "COMPILER_FLAGS" => "-fvisibility=default" }
    end
  end

  # ---- 3) Build settings: RESET path để không còn dính simulator ----
  target.build_configurations.each do |config|
    # LIBRARY_SEARCH_PATHS: bỏ mọi path simulator + airlift simulator, rồi thêm device
    lib_paths = Array(config.build_settings["LIBRARY_SEARCH_PATHS"] || ["$(inherited)"])
    lib_paths = lib_paths.reject { |p| p.to_s =~ /simulator/i }
    lib_paths << abs_lib_dir
    config.build_settings["LIBRARY_SEARCH_PATHS"] = lib_paths.uniq

    # HEADER_SEARCH_PATHS: tương tự
    hdr_paths = Array(config.build_settings["HEADER_SEARCH_PATHS"] || ["$(inherited)"])
    hdr_paths = hdr_paths.reject { |p| p.to_s =~ /simulator/i }
    hdr_paths << abs_hdr_dir
    config.build_settings["HEADER_SEARCH_PATHS"] = hdr_paths.uniq

    # LINKER FLAGS
    ldflags = ["$(inherited)"]
    ldflags << "-l#{lib_name}"
    ldflags << "-ObjC"
    ldflags << "-Wl,-export_dynamic"
    ldflags << "-Wl,-exported_symbol,_ALGetGrappaToken"
    ldflags << "-Wl,-exported_symbols_list,\"#{ENV["EXPORT_SYMBOLS_FILE"]}\""
    ldflags << "-Wl,-u,_ALGetGrappaToken"
    ldflags << "-Wl,-force_load,\"#{abs_lib_path}\""
    # ❌ ĐÃ BỎ: -Wl,-no_dead_strip_inits_and_terms (obsolete)
    config.build_settings["OTHER_LDFLAGS"] = ldflags

    config.build_settings["STRIP_INSTALLED_PRODUCT"] = "NO"
    config.build_settings["COPY_PHASE_STRIP"]        = "NO"
    config.build_settings["DEAD_CODE_STRIPPING"]     = "NO"
    config.build_settings["STRIP_STYLE"]             = "non-global"
  end

  project.save
  puts "✅ Đã cấu hình build settings (device slice, không còn simulator)"
'

echo "==> Bắt đầu Archive..."
XCB_ARGS=(
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -sdk iphoneos
  -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS"
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
)

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