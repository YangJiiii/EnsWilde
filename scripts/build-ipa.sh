#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-Release}"
SCHEME="EnsWilde"
PROJECT="EnsWilde.xcodeproj"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/EnsWilde.xcarchive"
EXPORT_DIR="$BUILD_DIR/Export"
APP_NAME="EnsWilde"
OTA_DIR="$BUILD_DIR/ota"

echo "==> [1/4] Checking files..."
AIRCARD_LIB="Frameworks/ios-arm64/libairlift_ffi.a"
AIRCARD_HEADERS="Frameworks/ios-arm64/Headers"
GRAPPA_H="Sources/GrappaHelper.h" 
GRAPPA_M="Sources/GrappaHelper.m"
GRAPPA_DIR="$(dirname "$GRAPPA_H")"

for f in "$AIRCARD_LIB" "$AIRCARD_HEADERS/airlift.h" "$GRAPPA_H" "$GRAPPA_M"; do
  if [ ! -f "$f" ]; then
    echo "❌ LỖI: Đéo tìm thấy $f"
    exit 1
  fi
done

echo "==> [2/4] Setting up build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR" "$OTA_DIR"

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

  # Xóa sổ libidevice_ffi.a (bị trùng symbol với Airlift)
  project.files.select { |f| f.path && f.path.end_with?("libidevice_ffi.a") }.each { |f| f.remove_from_project }

  target.frameworks_build_phase.files_references.dup.each do |f|
    next unless f
    target.frameworks_build_phase.remove_file_reference(f) if f.path&.end_with?("libairlift_ffi.a")
  end
  target.source_build_phase.files_references.dup.each do |f|
    next unless f
    target.source_build_phase.remove_file_reference(f) if f.path&.end_with?("GrappaHelper.m")
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
    ld_flags = ld_flags.reject { |s| s.to_s.include?("airlift_ffi") || s.to_s.include?("idevice_ffi") || s.to_s.include?("-all_load") }
    ld_flags << "-ObjC"
    ld_flags << "-lairlift_ffi"
    ld_flags << "-Wl,-u,_ALGetGrappaToken"
    config.build_settings["OTHER_LDFLAGS"] = ld_flags.uniq
  end
  project.save
'

echo "==> [4/4] Archiving, Signing & Building OTA..."
# 1. Archive (Codemagic tự inject cert vào keychain nên ko cần truyền CODE_SIGN_IDENTITY)
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -archivePath "$ARCHIVE_PATH" \
  | xcbeautify

# 2. Tìm Bundle ID và Team ID từ file mobileprovision (Codemagic tự cài nó vào thư mục Profiles)
PROFILE_PATH=$(find ~/Library/MobileDevice/Provisioning\ Profiles -name "*.mobileprovision" | head -n 1)
if [ -z "$PROFILE_PATH" ]; then
  echo "❌ Đéo tìm thấy Profile. Mày phải nạp cert trên Codemagic UI!"
  exit 1
fi
TEAM_ID=$(security cms -D -i "$PROFILE_PATH" | plutil -extract TeamIdentifier.0 raw -)
BUNDLE_ID=$(security cms -D -i "$PROFILE_PATH" | plutil -extract Entitlements.application-identifier raw - | cut -d '.' -f 2-)
PROFILE_NAME=$(security cms -D -i "$PROFILE_PATH" | plutil -extract Name raw -)

# 3. Tạo ExportOptions.plist
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_ID</key>
        <string>$PROFILE_NAME</string>
    </dict>
</dict>
</plist>
EOF

# 4. Export file IPA ĐÃ KÝ
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  | xcbeautify

# 5. Copy IPA sang thư mục OTA
cp "$EXPORT_DIR/$APP_NAME.ipa" "$OTA_DIR/"

# 6. Tạo manifest.plist cho OTA
# LƯU Ý: Thay "USERNAME" bằng username Github của mày
GITHUB_PAGES_URL="https://USERNAME.github.io/REPO_NAME/ota"
cat > "$OTA_DIR/manifest.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>items</key>
    <array>
        <dict>
            <key>assets</key>
            <array>
                <dict>
                    <key>kind</key>
                    <string>software-package</string>
                    <key>url</key>
                    <string>$GITHUB_PAGES_URL/$APP_NAME.ipa</string>
                </dict>
            </array>
            <key>metadata</key>
            <dict>
                <key>bundle-identifier</key>
                <string>$BUNDLE_ID</string>
                <key>bundle-version</key>
                <string>1.0.0</string>
                <key>kind</key>
                <string>software</string>
                <key>title</key>
                <string>$APP_NAME</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

# 7. Tạo trang HTML chứa nút cài
cat > "$OTA_DIR/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Cài Đặt $APP_NAME</title>
    <style>
        body { font-family: -apple-system, sans-serif; text-align: center; padding: 50px 20px; background: #000; color: #fff; }
        .btn { display: inline-block; padding: 15px 30px; background: #007aff; color: #fff; text-decoration: none; border-radius: 10px; font-weight: bold; font-size: 18px; margin-top: 20px; }
        .btn:active { background: #0056b3; }
    </style>
</head>
<body>
    <h1>$APP_NAME</h1>
    <p>Nhấn nút bên dưới để cài trực tiếp.</p>
    <a class="btn" href="itms-services://?action=download-manifest&url=$GITHUB_PAGES_URL/manifest.plist">Cài Đặt Ngay</a>
    <p style="color: #888; font-size: 12px;">Mở bằng Safari trên iPhone</p>
</body>
</html>
EOF

echo "✅ DONE: IPA đã ký và tạo xong link OTA tại $OTA_DIR"