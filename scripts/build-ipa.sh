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
    echo "❌ LỖI: Đéo tìm thấy $f"
    exit 1
  fi
done

echo "==> [2/4] Setting up build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> [3/4] Injecting Airlift + Grappa & Fixing Duplicate..."
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

  # 1. NUKE TẬN GỐC mọi PBXBuildFile trỏ tới libairlift_ffi.a / libidevice_ffi.a / GrappaHelper.m
  #    để chắc chắn không còn bản trùng nào trong bất kỳ phase nào.
  project.objects.dup.each do |_uuid, obj|
    next unless obj.is_a?(Xcodeproj::Project::Object::PBXBuildFile)
    path = obj.file_ref&.path.to_s
    next if path.empty?
    if path.end_with?("libairlift_ffi.a") ||
       path.end_with?("libidevice_ffi.a") ||
       path.end_with?("GrappaHelper.m")
      obj.remove_from_project
    end
  end

  # 2. XÓA file ref libidevice_ffi.a để khỏi trùng symbol với Airlift
  project.files.select { |f| f.path && f.path.end_with?("libidevice_ffi.a") }.each do |file_ref|
    file_ref.remove_from_project
    puts "🗑️ Đã xóa vĩnh viễn: #{file_ref.path}"
  end

  # 3. CHỈ ADD AIRLIFT VÀ GRAPPA (một lần duy nhất)
  lib_ref = project.files.find { |f| f.path == lib_path } || project.new_file(lib_path)
  target.frameworks_build_phase.add_file_reference(lib_ref)

  grappa_ref = project.files.find { |f| f.path == grappa_m_path } || project.new_file(grappa_m_path)
  target.source_build_phase.add_file_reference(grappa_ref)

  # 4. BUILD SETTINGS
  target.build_configurations.each do |config|
    # Header Search Paths
    h_paths = config.build_settings["HEADER_SEARCH_PATHS"] || ["$(inherited)"]
    h_paths = h_paths.reject { |p| p.to_s.include?("Frameworks/ios-arm64/Headers") || p.to_s.include?(grappa_dir.to_s) }
    h_paths << "$(PROJECT_DIR)/#{header_path}"
    h_paths << "$(PROJECT_DIR)/#{grappa_dir}"
    config.build_settings["HEADER_SEARCH_PATHS"] = h_paths.uniq

    # Library Search Paths
    lib_paths = config.build_settings["LIBRARY_SEARCH_PATHS"] || ["$(inherited)"]
    lib_paths = lib_paths.reject { |p| p.to_s.include?("Frameworks/ios-arm64") || p.to_s.include?("Sources/idevice") }
    lib_paths << "$(PROJECT_DIR)/Frameworks/ios-arm64"
    config.build_settings["LIBRARY_SEARCH_PATHS"] = lib_paths.uniq

    # OTHER_LDFLAGS — Lọc sạch flag cũ, thêm flag ép giữ Grappa symbol
    ld_flags = config.build_settings["OTHER_LDFLAGS"] || ["$(inherited)"]
    ld_flags = ld_flags.reject { |s|
      str = s.to_s
      str.include?("airlift_ffi") ||
      str.include?("idevice_ffi") ||
      str.include?("-all_load") ||
      str.include?("-exported_symbol") ||
      str.include?("-Wl,-u,") ||
      str == "-ObjC"
    }
    ld_flags << "-ObjC"
    ld_flags << "-lairlift_ffi"
    ld_flags << "-Wl,-exported_symbol,_ALGetGrappaToken"
    ld_flags << "-Wl,-u,_ALGetGrappaToken"
    config.build_settings["OTHER_LDFLAGS"] = ld_flags.uniq

    # Ép chết code signing (unsigned IPA)
    config.build_settings["CODE_SIGN_STYLE"] = "Manual"
    config.build_settings["CODE_SIGNING_ALLOWED"] = "NO"
    config.build_settings["CODE_SIGNING_REQUIRED"] = "NO"
    config.build_settings["CODE_SIGN_IDENTITY"] = ""
    config.build_settings["CODE_SIGN_ENTITLEMENTS"] = ""
    config.build_settings["DEVELOPMENT_TEAM"] = ""
    config.build_settings["PROVISIONING_PROFILE_SPECIFIER"] = ""
  end
  project.save
  puts "✅ Project config xong. Chỉ dùng Airlift, ép Linker giữ ALGetGrappaToken."
'

echo "==> [4/4] Archiving (Unsigned)..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="" EXPANDED_CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "❌ LỖI: Đéo tìm thấy file .app!" >&2
  exit 1
fi

APP_BASENAME="$(basename "$APP_PATH")"
rm -rf "$BUILD_DIR/Payload" && mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"

echo "==> [Stripping] Cạo sạch chữ ký..."
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/SC_Info"
rm -f  "$BUILD_DIR/Payload/${APP_BASENAME}/embedded.mobileprovision"
find "$BUILD_DIR/Payload/${APP_BASENAME}" -type f -perm +111 | while read -r file; do
    codesign --remove-signature "$file" 2>/dev/null || true
done
find "$BUILD_DIR/Payload/${APP_BASENAME}" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
find "$BUILD_DIR/Payload/${APP_BASENAME}" -name "embedded.mobileprovision" -type f -delete 2>/dev/null || true

(cd "$BUILD_DIR" && zip -qry "$IPA_PATH" Payload)
echo "✅ DONE: $IPA_PATH (UNSIGNED 100%)"