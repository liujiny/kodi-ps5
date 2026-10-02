#!/usr/bin/env bash
# Rebuild libcurl with a nonblocking drain when closing keep-alive sockets.
set -euo pipefail

export PS5_PAYLOAD_SDK="${PS5_PAYLOAD_SDK:-/opt/ps5-payload-sdk}"
WORK="${WORK:-$HOME/ps5-work}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=8.18.0
ARCHIVE="${CURL_ARCHIVE:-$WORK/downloads/curl-$VERSION.tar.xz}"
SRC="$WORK/libcurl-shutdown/curl-$VERSION"
PATCH="$HERE/patches/curl/0001-nonblocking-shutdown-drain.patch"
SDK_PC="$PS5_PAYLOAD_SDK/target/user/homebrew/lib/pkgconfig/libcurl.pc"

[ -f "$SDK_PC" ] || { echo "!! libcurl is missing from the SDK"; exit 1; }
grep -qx "Version: $VERSION" "$SDK_PC" || {
  echo "!! this patch targets the installed libcurl $VERSION"; exit 1;
}

if [ ! -f "$ARCHIVE" ]; then
  mkdir -p "$(dirname "$ARCHIVE")"
  curl --fail --location --retry 3 "https://curl.se/download/curl-$VERSION.tar.xz" -o "$ARCHIVE"
fi
printf '%s  %s\n' 40df79166e74aa20149365e11ee4c798a46ad57c34e4f68fd13100e2c9a91946 "$ARCHIVE" | sha256sum --check
if [ ! -d "$SRC" ]; then
  mkdir -p "$(dirname "$SRC")"
  tar -xJf "$ARCHIVE" -C "$(dirname "$SRC")"
fi
if patch --directory="$SRC" --dry-run --fuzz=0 -p1 < "$PATCH" >/dev/null 2>&1; then
  patch --directory="$SRC" --fuzz=0 -p1 < "$PATCH"
else
  patch --directory="$SRC" --reverse --dry-run --fuzz=0 -p1 < "$PATCH" >/dev/null || {
    echo "!! libcurl source does not match the shutdown patch"; exit 1;
  }
fi

source "$PS5_PAYLOAD_SDK/toolchain/prospero.sh"
cd "$SRC"
./configure --prefix="$PS5_HBROOT" --host=x86_64-pc-freebsd \
  --enable-static --disable-shared --disable-docs \
  --with-openssl --with-ca-bundle="$PS5_HBROOT/etc/ca-bundle.crt" \
  --with-libpsl --with-zlib --with-zstd --without-brotli \
  --without-nghttp2 --without-nghttp3 --without-ngtcp2 \
  --without-libidn2 --without-libssh --without-libssh2 \
  --without-librtmp --without-gssapi
make -j"${JOBS:-3}"
make -C lib DESTDIR="$PS5_PAYLOAD_SDK/target" install

KODI_BUILD="${KODI_BUILD:-${BUILD:-$HOME/kodi-ps5-build}}"
source "$HERE/scripts/lib/sysroot-changed.sh"
sysroot_changed
echo "libcurl shutdown fix installed. Rebuild Kodi and run scripts/30-deploy.sh."
