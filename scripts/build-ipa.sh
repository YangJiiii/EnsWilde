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
# KIỂM TRA FRAMEWORK ĐÃ CÓ SẴN CHƯA (Không build Rust nữa)
# =============================================================================
FRAMEWORK_DIR="Frameworks/AirliftFFI.framework"
if [ ! -d "$FRAMEWORK_DIR" ]; then
    echo "❌ Đ*o thấy thư mục $FRAMEWORK_DIR đâu cả. Boss man kiểm tra lại xem đã kéo thư mục Frameworks vào chưa?"
    exit 1
fi
echo "✅ Đã tìm thấy AirliftFFI.framework sẵn có!"

# =============================================================================
# INJECT VÀO XCODE BẰNG RUBY
# =============================================================================
echo "==> Injecting AirliftFFI & GrappaHelper vào Xcode project..."
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project_path = "EnsWilde.xcodeproj"
  framework_path = "Frameworks/AirliftFFI.framework"
  
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == "EnsWilde" }
  
  unless target.nil?
    # 1. Thêm Framework vào Link Binary With Libraries
    file_ref = project.new_file(framework_path)
    target.frameworks_build_phase.add_file_reference(file_ref)
    
    # 2. Nhúng Framework (Embed Frameworks)
    embed_phase = target.copy_files_build_phases.find { |p| p.name == "Embed Frameworks" } 
    if embed_phase.nil?
      embed_phase = target.new_copy_files_build_phase("Embed Frameworks")
      embed_phase.dst_subfolder_spec = "10"
    end
    build_file = embed_phase.add_file_reference(file_ref)
    build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
    
    # 3. Tìm và add GrappaHelper.m vào Compile Sources
    grappa_m_path = Dir.glob("**/GrappaHelper.m").first
    if grappa_m_path
      # Kiểm tra xem đã có trong project chưa để tránh duplicate
      unless project.files.any? { |f| f.path == grappa_m_path }
        grappa_ref = project.new_file(grappa_m_path)
        target.add_file_references([grappa_ref])
        puts "✅ Đã add GrappaHelper.m vào Compile Sources"
      end
    else
      puts "⚠️ CẢNH BÁO: Đ*o tìm thấy file GrappaHelper.m trong repo!"
    end

    # 4. Cấu hình Build Settings cho Target
    target.build_configurations.each do |config|
      config.build_settings["FRAMEWORK_SEARCH_PATHS"] ||= ["$(inherited)"]
      config.build_settings["FRAMEWORK_SEARCH_PATHS"] << "$(PROJECT_DIR)/Frameworks"
      
      config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]
      config.build_settings["OTHER_LDFLAGS"] << "-ObjC" # Load Obj-C classes (Grappa)
    end
    
    project.save
    puts "✅ Xong! Đã cấu hình Xcode project."
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