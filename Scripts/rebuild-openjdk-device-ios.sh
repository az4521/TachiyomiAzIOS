#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_root="$repository_root/Vendor/OpenJDK"
framework_root="$vendor_root/OpenJDK.xcframework/ios-arm64"
output_library="$framework_root/libdevice.a"
deployment_target="15.0"
# This is the first Java 27 mobile merge after the transient upstream state
# that dropped PLATFORM_EXTRACT_VARS_FROM_OS support for ios.
mobile_revision="2ddf7f319f2fd177c1aa35d7928936ecd089550c"
symbol_keeper_revision="f8524c91c012040e40e7f8af34e7a0f11af0da83"
symbol_keeper_sha256="d961417005414a5ef35eb2deb229a10c8b32f79acbc5f8661085b7f55b160a83"
libffi_sha256="4f39fd1d53fbd69d1bdbd915413077d130daa3f6792d1b3a03a690a9cbd4dea3"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "The iOS OpenJDK runtime must be rebuilt on macOS." >&2
    exit 1
fi

for executable in git curl unzip make libtool xcrun; do
    command -v "$executable" >/dev/null || {
        echo "$executable is required." >&2
        exit 1
    }
done

if [[ ! -f "$output_library" ]]; then
    echo "Bootstrap OpenJDK.xcframework before rebuilding its device slice." >&2
    exit 1
fi

minimum_version() {
    local library="$1"
    local probe_root
    local member
    probe_root="$(mktemp -d "${TMPDIR:-/tmp}/tachiaz-openjdk-probe.XXXXXX")"
    member="$(ar -t "$library" | grep -m1 '^abstractCompiler\.o$' || true)"
    if [[ -z "$member" ]]; then
        rm -rf "$probe_root"
        return 1
    fi
    (
        cd "$probe_root"
        ar -x "$library" "$member"
        xcrun vtool -show-build "$member" 2>/dev/null |
            awk '/minos/ { print $2; exit }'
    )
    rm -rf "$probe_root"
}

if [[ "$(minimum_version "$output_library" || true)" == "$deployment_target" ]]; then
    echo "OpenJDK device runtime already targets iOS $deployment_target"
    exit 0
fi

build_root="$(mktemp -d "${TMPDIR:-/tmp}/tachiaz-openjdk-build.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT
support_root="$build_root/support"
mobile_root="$build_root/mobile"
symbol_keeper="$build_root/symbol_keeper.cpp"
libffi_archive="$build_root/libffi-ios.zip"
sdk_root="$(xcrun --sdk iphoneos --show-sdk-path)"

curl --fail --location \
    --output "$symbol_keeper" \
    "https://raw.githubusercontent.com/openjdk-mobile/ios-tools/$symbol_keeper_revision/openjdk-ext/src/hotspot/symbol_keeper.cpp"
curl --fail --location \
    --output "$libffi_archive" \
    "https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios.zip"

checksum() {
    shasum -a 256 "$1" | awk '{ print $1 }'
}

[[ "$(checksum "$symbol_keeper")" == "$symbol_keeper_sha256" ]] || {
    echo "OpenJDK symbol keeper checksum mismatch." >&2
    exit 1
}
[[ "$(checksum "$libffi_archive")" == "$libffi_sha256" ]] || {
    echo "OpenJDK libffi checksum mismatch." >&2
    exit 1
}

mkdir -p "$support_root" "$mobile_root"
unzip -q "$libffi_archive" -d "$support_root"
git -C "$mobile_root" init
git -C "$mobile_root" remote add origin https://github.com/openjdk/mobile.git
git -C "$mobile_root" fetch --depth=1 origin "$mobile_revision"
git -C "$mobile_root" checkout --detach FETCH_HEAD
cp "$symbol_keeper" "$mobile_root/src/hotspot/os/bsd/symbol_keeper.cpp"

(
    cd "$mobile_root"
    bash configure \
        --with-conf-name=ios-aarch64-zero-release \
        --disable-warnings-as-errors \
        --openjdk-target=aarch64-macos-ios \
        --with-sysroot="$sdk_root" \
        --with-libffi-include="$support_root/include/ffi" \
        --with-libffi-lib="$support_root" \
        --with-extra-cflags="-miphoneos-version-min=$deployment_target" \
        --with-extra-cxxflags="-miphoneos-version-min=$deployment_target" \
        --with-extra-ldflags="-miphoneos-version-min=$deployment_target" \
        --with-cups-include="$(xcrun --sdk macosx --show-sdk-path)/usr/include"
    make LOG=info CONF=ios-aarch64-zero-release static-libs-image
)

static_root="$mobile_root/build/ios-aarch64-zero-release/images/static-libs/lib"
rebuilt_library="$build_root/libdevice.a"
libtool -static -o "$rebuilt_library" \
    "$static_root/zero/libjvm.a" \
    "$support_root/libffi.a" \
    "$static_root/libjava.a" \
    "$static_root/libzip.a" \
    "$static_root/libnet.a" \
    "$static_root/libnio.a" \
    "$static_root/libjimage.a"

actual_target="$(minimum_version "$rebuilt_library" || true)"
if [[ "$actual_target" != "$deployment_target" ]]; then
    echo "Rebuilt OpenJDK runtime targets iOS ${actual_target:-unknown}, expected $deployment_target." >&2
    exit 1
fi

cp "$rebuilt_library" "$output_library"
cp -R \
    "$mobile_root/build/ios-aarch64-zero-release/jdk/include/." \
    "$framework_root/Headers/"
if [[ -d "$framework_root/Headers/ios" ]]; then
    cp -R "$framework_root/Headers/ios/." "$framework_root/Headers/"
fi

echo "Rebuilt OpenJDK device runtime for iOS $deployment_target"
