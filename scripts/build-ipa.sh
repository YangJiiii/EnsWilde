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

if [ -z "$LIB_PATH" ]; then
  LIB_PATH=$(find . -type f -name "*.a" \
    ! -path "*simulator*" ! -path "*x86_64*" 2>/dev/null | head -n 1 || true)
fi

if [ -z "$LIB_PATH" ]; then
  echo "❌ LỖI: Không tìm thấy slice iOS-device (.a) nào (đã loại trừ simulator)."
  exit 1
fi
LIB_DIR=$(dirname "$LIB_PATH")
echo "✅ Tìm thấy Lib (device): $LIB_PATH"

HEADER_FILE=$(find . -type f -name "airlift.h" \
  ! -path "*simulator*" ! -path "*x86_64*" 2>/dev/null | head -n 1 || true)

if [ -z "$HEADER_FILE" ]; then
  echo "❌ LỖI: Không tìm thấy airlift.h cho device slice."
  exit 1
fi
HEADER_DIR=$(dirname "$HEADER_FILE")
echo "✅ Tìm thấy Header (device): $HEADER_FILE"
# ==============================================================================

# ==============================================================================
# FIX DUPLICATE SYMBOL: _rust_eh_personality
# ==============================================================================
echo "==> Fix duplicate symbol: weaken Rust std symbols trong libairlift_ffi.a..."

AIRLIFT_LIB_ABS="$(cd "$LIB_DIR" && pwd)/$(basename "$LIB_PATH")"
LLVM_OBJCOPY="$(xcrun -f llvm-objcopy 2>/dev/null || true)"

if [ -z "$LLVM_OBJCOPY" ] || [ ! -x "$LLVM_OBJCOPY" ]; then
  for c in /opt/homebrew/opt/llvm/bin/llvm-objcopy /usr/local/opt/llvm/bin/llvm-objcopy; do
    if [ -x "$c" ]; then LLVM_OBJCOPY="$c"; break; fi
  done
fi

if [ -z "$LLVM_OBJCOPY" ] || [ ! -x "$LLVM_OBJCOPY" ]; then
  echo "    → Không tìm thấy llvm-objcopy. Đang cài đặt qua Homebrew..."
  if command -v brew >/dev/null 2>&1; then
    brew install llvm >/dev/null 2>&1 || true
    BREW_PREFIX="$(brew --prefix)"
    LLVM_OBJCOPY="${BREW_PREFIX}/opt/llvm/bin/llvm-objcopy"
  fi
fi

if [ -z "$LLVM_OBJCOPY" ] || [ ! -x "$LLVM_OBJCOPY" ]; then
  echo "❌ Vẫn không tìm thấy llvm-objcopy sau khi cài đặt."
  exit 1
fi
echo "    → llvm-objcopy: $LLVM_OBJCOPY"

if [ ! -f "${AIRLIFT_LIB_ABS}.orig" ]; then
  cp "$AIRLIFT_LIB_ABS" "${AIRLIFT_LIB_ABS}.orig"
else
  cp "${AIRLIFT_LIB_ABS}.orig" "$AIRLIFT_LIB_ABS"
fi

"$LLVM_OBJCOPY" --wildcard --weaken-symbol='_rust_*' "$AIRLIFT_LIB_ABS"
echo "✅ Hoàn tất fix duplicate symbol."
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

  unless target.frameworks_build_phase.files.any? { |f|
    f.file_ref && f.file_ref.path && f.file_ref.path.include?(File.basename(abs_lib_path))
  }
    lib_ref = project.new_file(abs_lib_path)
    target.frameworks_build_phase.add_file_reference(lib_ref)
  end

  grappa_m_path = Dir.glob("**/GrappaHelper.m").first
  if grappa_m_path
    abs_grappa = File.expand_path(grappa_m_path)
    seen = false
    target.source_build_phase.files.dup.each do |bf|
      path = bf.file_ref && bf.file_ref.path
      next unless path && path.include?("GrappaHelper.m")
      if seen
        bf.remove_from_project
      else
        seen = true
        bf.settings = { "COMPILER_FLAGS" => "-fvisibility=default" }
      end
    end
    unless seen
      file_ref = project.files.find { |f| f.path && f.path.include?("GrappaHelper.m") } || project.new_file(abs_grappa)
      bf = target.source_build_phase.add_file_reference(file_ref, true)
      bf.settings = { "COMPILER_FLAGS" => "-fvisibility=default" }
    end
  end

  target.build_configurations.each do |config|
    lib_paths = Array(config.build_settings["LIBRARY_SEARCH_PATHS"] || ["$(inherited)"])
    lib_paths = lib_paths.reject { |p| p.to_s =~ /simulator/i }
    lib_paths << abs_lib_dir
    config.build_settings["LIBRARY_SEARCH_PATHS"] = lib_paths.uniq

    hdr_paths = Array(config.build_settings["HEADER_SEARCH_PATHS"] || ["$(inherited)"])
    hdr_paths = hdr_paths.reject { |p| p.to_s =~ /simulator/i }
    hdr_paths << abs_hdr_dir
    config.build_settings["HEADER_SEARCH_PATHS"] = hdr_paths.uniq

    ldflags = ["$(inherited)"]
    ldflags << "-l#{lib_name}"
    ldflags << "-ObjC"
    ldflags << "-Wl,-export_dynamic"
    ldflags << "-Wl,-exported_symbol,_ALGetGrappaToken"
    ldflags << "-Wl,-exported_symbols_list,\"#{ENV["EXPORT_SYMBOLS_FILE"]}\""
    ldflags << "-Wl,-u,_ALGetGrappaToken"
    ldflags << "-Wl,-force_load,\"#{abs_lib_path}\""
    config.build_settings["OTHER_LDFLAGS"] = ldflags

    config.build_settings["STRIP_INSTALLED_PRODUCT"] = "NO"
    config.build_settings["COPY_PHASE_STRIP"]        = "NO"
    config.build_settings["DEAD_CODE_STRIPPING"]     = "NO"
    config.build_settings["STRIP_STYLE"]             = "non-global"
  end

  project.save
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

# Copy file entitlements ra ngoài
if [ -f "EnsWilde.entitlements" ]; then
    cp "EnsWilde.entitlements" "$BUILD_DIR/"
    echo "✅ Đã copy EnsWilde.entitlements ra thư mục build"
fi

echo "🔥 Done: $IPA_PATH"