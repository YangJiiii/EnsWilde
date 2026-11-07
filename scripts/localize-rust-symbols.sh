#!/bin/bash
# Localize các symbol nội bộ Rust (_rust_*) trong libairlift_ffi.a
# để tránh trùng lặp _rust_eh_personality với libidevice_ffi.a.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AIRLIFT_LIB="./AirliftFFI.xcframework/ios-arm64/libairlift_ffi.a"
IDEVICE_LIB="./Sources/idevice/libidevice_ffi.a"

echo "==> Localize Rust symbols trong $AIRLIFT_LIB"

if [[ ! -f "$AIRLIFT_LIB" ]]; then
  echo "❌ Không tìm thấy $AIRLIFT_LIB"
  exit 1
fi
if [[ ! -f "$IDEVICE_LIB" ]]; then
  echo "❌ Không tìm thấy $IDEVICE_LIB"
  exit 1
fi

# --- Tìm llvm-objcopy ---
OBJCOPY=""
if command -v llvm-objcopy >/dev/null 2>&1; then
  OBJCOPY="$(command -v llvm-objcopy)"
elif command -v rustup >/dev/null 2>&1; then
  echo "    → Cài llvm-tools-preview qua rustup..."
  rustup component add llvm-tools-preview >/dev/null 2>&1 || true
  RUSTUP_HOME_DIR="$(rustup show home 2>/dev/null || echo "$HOME/.rustup")"
  OBJCOPY="$(find "$RUSTUP_HOME_DIR/toolchains" -name llvm-objcopy -type f 2>/dev/null | head -1)"
elif [[ -x "/opt/homebrew/opt/llvm/bin/llvm-objcopy" ]]; then
  OBJCOPY="/opt/homebrew/opt/llvm/bin/llvm-objcopy"
elif [[ -x "/usr/local/opt/llvm/bin/llvm-objcopy" ]]; then
  OBJCOPY="/usr/local/opt/llvm/bin/llvm-objcopy"
fi

if [[ -z "$OBJCOPY" || ! -x "$OBJCOPY" ]]; then
  echo "❌ Không tìm thấy llvm-objcopy. Cài bằng: brew install llvm"
  exit 1
fi
echo "    → Dùng llvm-objcopy: $OBJCOPY"

# --- Kiểm tra trước ---
if nm -g "$AIRLIFT_LIB" 2>/dev/null | grep -qE ' _rust_eh_personality$'; then
  echo "    → Phát hiện _rust_eh_personality là GLOBAL trong libairlift_ffi.a (cần localize)"
else
  echo "    → Không thấy _rust_eh_personality global trong libairlift_ffi.a (có thể đã localize rồi, bỏ qua)"
  exit 0
fi

# --- Backup 1 lần duy nhất ---
if [[ ! -f "${AIRLIFT_LIB}.orig" ]]; then
  cp "$AIRLIFT_LIB" "${AIRLIFT_LIB}.orig"
  echo "    → Đã backup: ${AIRLIFT_LIB}.orig"
fi

# --- Localize toàn bộ symbol bắt đầu bằng _rust_ ---
"$OBJCOPY" --wildcard-localize-symbol='_rust_*' "$AIRLIFT_LIB"

# --- Verify ---
echo "==> Kiểm tra sau khi localize:"
if nm -g "$AIRLIFT_LIB" 2>/dev/null | grep -qE ' _rust_eh_personality$'; then
  echo "❌ Thất bại: _rust_eh_personality vẫn còn GLOBAL"
  exit 1
fi
echo "✅ _rust_eh_personality đã thành LOCAL (hoặc đã biến mất khỏi global symbol table)"
echo "✅ Hoàn tất localize."
