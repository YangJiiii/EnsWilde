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

echo "==> [1/5] Detect Provisioning Profile..."
PROFILE_PATH=$(find ~/Library/MobileDevice/Provisioning\ Profiles -name "*.mobileprovision" 2>/dev/null | head -n 1)
if [ -z "$PROFILE_PATH" ]; then
  echo "❌ Đéo tìm thấy profile nào trên máy. Codemagic chưa cài profile!"
  exit 1
fi
echo "📄 Profile: $PROFILE_PATH"

# Đọc thông tin từ profile
PROFILE_DICT=$(security cms -D -i "$PROFILE_PATH")
PROFILE_NAME=$(echo "$PROFILE_DICT" | plutil -extract Name raw - 2>/dev/null || echo "Unknown")
TEAM_ID=$(echo "$PROFILE_DICT" | plutil -extract TeamIdentifier.0 raw - 2>/dev/null || echo "")
APP_ID=$(echo "$PROFILE_DICT" | plutil -extract Entitlements.application-identifier raw - 2>/dev/null || echo "")
BUNDLE_ID=$(echo "$APP_ID" | cut -d '.' -f 2-)
PROFILE_UUID=$(echo "$PROFILE_DICT" | plutil -extract UUID raw - 2>/dev/null || echo "")

echo "🔍 Profile Name:    $PROFILE_NAME"
echo "🔍 Team ID:         $TEAM_ID"
echo "🔍 Bundle ID:       $BUNDLE_ID"
echo "🔍 Profile UUID:    $PROFILE_UUID"

if [ -z "$TEAM_ID" ] || [ -z "$BUNDLE_ID" ]; then
  echo "❌ Không đọc được thông tin profile. File có thể bị hỏng."
  exit 1
fi

echo "==> [2/5] Injecting Airlift + Grappa & Fixing Duplicate..."
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

rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR" "$OTA_DIR"

gem install xcodeproj --no-document >/dev/null 2>&1 || true
export AIRCARD_LIB AIRCARD_HEADERS GRAPPA_M GRAPPA_DIR BUNDLE_ID TEAM_ID PROFILE_UUID

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.open("EnsWilde.xcodeproj")
  target = project.targets.find { |t| t.name == "EnsWilde" }
  exit 1 if target.nil?

  lib_path = ENV["AIRCARD_LIB"]
  grappa_m_path = ENV["GRAPPA_M"]
  grappa_dir = ENV["GRAPPA_DIR"]
  header_path = ENV["AIRCARD_HEADERS"]
  bundle_id = ENV["BUNDLE_ID"]
  team_id = ENV["TEAM_ID"]
  profile_uuid = ENV["PROFILE_UUID"]

  # Fix duplicate GrappaHelper.m — chỉ giữ 1 ref duy nhất
  grappa_refs = target.source_build_phase.files_references.select { |f| f&.path&.end_with?("GrappaHelper.m") }
  grappa_refs.drop(1).each do |f|
    target.source_build_phase.remove_file_reference(f)
    puts "🗑️ Xóa duplicate GrappaHelper.m"
  end

  # Xóa libidevice_ffi.a cũ để khỏi trùng symbol
  project.files.select { |f| f.path && f.path.end_with?("libidevice_ffi.a") }.each { |f| f.remove_from_project }

  # Reset và add lại Airlift
  target.frameworks_build_phase.files_references.dup.each do |f|
    next unless f
    target.frameworks_build_phase.remove_file_reference(f) if f.path&.end_with?("libairlift_ffi.a")
  end

  lib_ref = project.files.find { |f| f.path == lib_path } || project.new_file(lib_path)
  target.frameworks_build_phase.add_file_reference(lib_ref)

  # Thêm lại GrappaHelper.m nếu chưa có
  if target.source_build_phase.files_references.none? { |f| f&.path&.end_with?("GrappaHelper.m") }
    grappa_ref = project.files.find { |f| f.path == grappa_m_path } || project.new_file(grappa_m_path)
    target.source_build_phase.add_file_reference(grappa_ref)
  end

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

    # Ép manual signing với profile đã detect
    config.build_settings["CODE_SIGN_STYLE"] = "Manual"
    config.build_settings["CODE_SIGN_IDENTITY"] = "Apple Development"
    config.build_settings["CODE_SIGN_IDENTITY[sdk=iphoneos*]"] = "Apple Development"
    config.build_settings["DEVELOPMENT_TEAM"] = team_id
    config.build_settings["PROVISIONING_PROFILE_SPECIFIER"] = profile_uuid
    config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id
    config.build_settings["CODE_SIGN_ENTITLEMENTS"] = ""
  end
  project.save
  puts "✅ Project config: Bundle=#{bundle_id}, Team=#{team_id}, UUID=#{profile_uuid}"
'

echo "==> [3/5] Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE="Manual" \
  CODE_SIGN_IDENTITY="Apple Development" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

echo "==> [4/5] Exporting signed IPA..."
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Apple Development</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_ID</key>
        <string>$PROFILE_NAME</string>
    </dict>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates

# Copy IPA đã ký sang thư mục OTA
cp "$EXPORT_DIR/$APP_NAME.ipa" "$OTA_DIR/"

echo "==> [5/5] Tạo manifest.plist & index.html cho OTA..."
# SỬA 2 DÒNG DƯỚI ĐÂY THÀNH USERNAME/REPO THẬT CỦA MÀY
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

# Trang HTML cài đặt (dùng file bạn đã có, hoặc tạo bản gọn)
cat > "$OTA_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Cài Đặt $APP_NAME</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,sans-serif;background:linear-gradient(135deg,#1a1a2e,#16213e,#0f3460);color:#fff;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
.box{background:rgba(255,255,255,.05);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,.1);border-radius:24px;padding:40px 30px;max-width:420px;width:100%;text-align:center;box-shadow:0 25px 50px rgba(0,0,0,.5)}
h1{font-size:28px;margin-bottom:8px;background:linear-gradient(135deg,#fff,#a8c0ff);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
p{color:#ccd6f6;font-size:15px;line-height:1.6;margin-bottom:24px}
a.btn{display:inline-block;width:100%;padding:18px 30px;background:linear-gradient(135deg,#007aff,#5856d6);color:#fff;text-decoration:none;border-radius:16px;font-weight:600;font-size:18px;box-shadow:0 10px 30px rgba(0,122,255,.4);transition:all .3s}
a.btn:active{transform:scale(.98)}
.warn{margin-top:20px;padding:14px;background:rgba(255,149,0,.1);border:1px solid rgba(255,149,0,.3);border-radius:12px;font-size:13px;color:#ffb84d;line-height:1.5}
</style>
</head>
<body>
<div class="box">
<h1>$APP_NAME</h1>
<p>Bấm nút bên dưới để cài trực tiếp lên iPhone.</p>
<a id="btn" class="btn" href="itms-services://?action=download-manifest&url=$GITHUB_PAGES_URL/manifest.plist">Cài Đặt Ngay</a>
<div class="warn">⚠️ Mở bằng <b>Safari</b> trên iPhone để cài được. Chrome/Edge không hỗ trợ.</div>
</div>
<script>
var ua=navigator.userAgent.toLowerCase();
var isIOS=/iphone|ipad|ipod/.test(ua);
var isSafari=/safari/.test(ua)&&!/chrome|crios|fxios/.test(ua);
if(isIOS&&isSafari){setTimeout(function(){window.location.href=document.getElementById('btn').href},2000)}
</script>
</body>
</html>
EOF

echo "✅ DONE: IPA đã ký + OTA sẵn sàng tại $OTA_DIR"
echo "📦 IPA path: $OTA_DIR/$APP_NAME.ipa"