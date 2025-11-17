#!/bin/bash
# Post-build script to fix macOS Git libraries
# Run this after: flutter build macos

APP_MACOS="app/build/macos/Build/Products/Debug/Parachute.app/Contents/MacOS"
LIBSSH2_PATH="$APP_MACOS/libssh2.1.dylib"
OPENSSL_SOURCE="/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib"

if [ ! -f "$LIBSSH2_PATH" ]; then
    echo "⚠️  App not found. Build first with: cd app && flutter build macos --debug"
    exit 1
fi

echo "Fixing macOS Git libraries..."

# Copy OpenSSL 3.x to app bundle
if [ -f "$OPENSSL_SOURCE" ]; then
    cp "$OPENSSL_SOURCE" "$APP_MACOS/libcrypto.3.dylib"
    install_name_tool -id @executable_path/libcrypto.3.dylib "$APP_MACOS/libcrypto.3.dylib"
    echo "✅ Copied OpenSSL 3.x to app bundle"
else
    echo "⚠️  Homebrew OpenSSL 3.x not found at $OPENSSL_SOURCE"
    exit 1
fi

# Fix libssh2 to use bundled OpenSSL
install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib @executable_path/libcrypto.3.dylib "$LIBSSH2_PATH" 2>/dev/null
install_name_tool -change /usr/lib/libcrypto.dylib @executable_path/libcrypto.3.dylib "$LIBSSH2_PATH" 2>/dev/null

# Re-sign libraries (CRITICAL - required after modifying with install_name_tool)
codesign --force --sign - "$APP_MACOS/libcrypto.3.dylib"
codesign --force --sign - "$LIBSSH2_PATH"

echo "✅ macOS Git libraries fixed and re-signed"
