#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_root="$repository_root/Vendor/OpenJDK"
deployment_target="15.0"
mobile_revision="ad8bb1b065bf230d193a1dfd0ebd39a8b1fedf53"
builder_revision="0a753240e2b143137e73593c48d646a4956c2351"
symbol_keeper_sha256="ec02a950b2c630b234aa393abdf48efe7ce95c3a637c189e0a2e492e8ec316db"
device_libffi_sha256="4f39fd1d53fbd69d1bdbd915413077d130daa3f6792d1b3a03a690a9cbd4dea3"
simulator_libffi_sha256="701b522e3eff0263f18d4a9e487f0a7ac30050fb2af20e86b6849daa14f5781f"
stamp_value="openjdk-mobile-$mobile_revision-ios-$deployment_target-v4"
stamp_file="$vendor_root/.ios-runtime"

if [[ -f "$stamp_file" ]] && [[ "$(<"$stamp_file")" == "$stamp_value" ]]; then
    if [[
        -f "$vendor_root/OpenJDK.xcframework/Info.plist" &&
        -f "$vendor_root/java_bundle-device/lib/modules" &&
        -f "$vendor_root/java_bundle-simulator/lib/modules"
    ]]; then
        echo "OpenJDK iOS runtime cache is current"
        exit 0
    fi
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "The OpenJDK iOS runtime must be built on macOS." >&2
    exit 1
fi

for executable in \
    git curl unzip make libtool ar xcrun xcodebuild \
    java shasum ditto
do
    command -v "$executable" >/dev/null || {
        echo "$executable is required." >&2
        exit 1
    }
done

java_feature="$(java -version 2>&1 | awk -F '[\".]' '/version/ { print $2; exit }')"
if [[ "$java_feature" != "24" ]]; then
    # This source revision predates JDK 26's LAZY_CONSTANTS preview metadata.
    # Using JDK 26 as the boot JDK breaks the interim langtools -Werror build.
    echo "OpenJDK 24 is required as the OpenJDK Mobile 26 boot JDK." >&2
    exit 1
fi

build_root="$(mktemp -d "${TMPDIR:-/tmp}/tachiaz-openjdk-ios15.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT
mobile_root="$build_root/mobile"
device_support="$build_root/device-support"
simulator_support="$build_root/simulator-support"
symbol_keeper="$build_root/symbol_keeper.cpp"
device_libffi="$build_root/libffi-ios.zip"
simulator_libffi="$build_root/libffi-ios-sim.zip"

download() {
    curl --fail --location --output "$2" "$1"
}

checksum() {
    shasum -a 256 "$1" | awk '{ print $1 }'
}

verify() {
    local path="$1"
    local expected="$2"
    local actual
    actual="$(checksum "$path")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Checksum mismatch for $path" >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 1
    fi
}

download \
    "https://raw.githubusercontent.com/openjdk-mobile/ios-tools/$builder_revision/openjdk-ext/src/hotspot/symbol_keeper.cpp" \
    "$symbol_keeper"
download \
    "https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios.zip" \
    "$device_libffi"
download \
    "https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios-sim.zip" \
    "$simulator_libffi"
verify "$symbol_keeper" "$symbol_keeper_sha256"
verify "$device_libffi" "$device_libffi_sha256"
verify "$simulator_libffi" "$simulator_libffi_sha256"

mkdir -p "$mobile_root" "$device_support" "$simulator_support"
unzip -q "$device_libffi" -d "$device_support"
unzip -q "$simulator_libffi" -d "$simulator_support"

# The published simulator libffi is universal (x86_64 + arm64), while this
# OpenJDK configuration builds arm64 only. Passing the universal archive to
# libtool would make the combined runtime universal too, with an x86_64 slice
# containing libffi but none of the JVM. Keep only the complete arm64 slice.
simulator_libffi_arm64="$build_root/libffi-ios-simulator-arm64.a"
xcrun lipo -thin arm64 \
    "$simulator_support/libffi.a" \
    -output "$simulator_libffi_arm64"

git -C "$mobile_root" init
git -C "$mobile_root" remote add origin https://github.com/openjdk/mobile.git
git -C "$mobile_root" fetch --depth=1 origin "$mobile_revision"
git -C "$mobile_root" checkout --detach FETCH_HEAD

device_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
macos_sdk="$(xcrun --sdk macosx --show-sdk-path)"

(
    cd "$mobile_root"

    # jlink validates an internal build signature in java.base. Build the
    # image tools from this exact source revision rather than using a released
    # JDK 26 whose signature may differ. This normal macOS build must happen
    # before symbol_keeper.cpp is added for the static iOS builds.
    bash configure \
        --with-conf-name=macos-aarch64 \
        --disable-warnings-as-errors
    make LOG=info CONF=macos-aarch64 jdk-image

    cp "$symbol_keeper" src/hotspot/os/bsd/symbol_keeper.cpp

    bash configure \
        --with-conf-name=ios-aarch64-zero-release \
        --disable-warnings-as-errors \
        --openjdk-target=aarch64-macos-ios \
        --with-sysroot="$device_sdk" \
        --with-libffi-include="$device_support/include/ffi" \
        --with-libffi-lib="$device_support" \
        --with-extra-cflags="-miphoneos-version-min=$deployment_target" \
        --with-extra-cxxflags="-miphoneos-version-min=$deployment_target" \
        --with-extra-ldflags="-miphoneos-version-min=$deployment_target" \
        --with-cups-include="$macos_sdk/usr/include"
    make LOG=info CONF=ios-aarch64-zero-release static-libs-image

    bash configure \
        --with-conf-name=iossim-aarch64-zero-release \
        --disable-warnings-as-errors \
        --openjdk-target=aarch64-macos-ios \
        --with-sysroot="$simulator_sdk" \
        --with-libffi-include="$simulator_support/include/ffi" \
        --with-libffi-lib="$simulator_support" \
        --with-extra-cflags="-target arm64-apple-ios${deployment_target}-simulator -mios-simulator-version-min=$deployment_target" \
        --with-extra-cxxflags="-target arm64-apple-ios${deployment_target}-simulator -mios-simulator-version-min=$deployment_target" \
        --with-extra-ldflags="-target arm64-apple-ios${deployment_target}-simulator -mios-simulator-version-min=$deployment_target" \
        --with-cups-include="$macos_sdk/usr/include"
    make LOG=info CONF=iossim-aarch64-zero-release static-libs-image
)

image_java_home="$mobile_root/build/macos-aarch64/images/jdk"
if [[
    ! -x "$image_java_home/bin/jmod" ||
    ! -x "$image_java_home/bin/jlink"
]]; then
    echo "The matching macOS JDK image tools were not built." >&2
    exit 1
fi

combine_runtime() {
    local configuration="$1"
    local libffi="$2"
    local destination="$3"
    local static_root="$mobile_root/build/$configuration/images/static-libs/lib"
    libtool -static -o "$destination" \
        "$static_root/zero/libjvm.a" \
        "$libffi" \
        "$static_root/libjava.a" \
        "$static_root/libzip.a" \
        "$static_root/libnet.a" \
        "$static_root/libnio.a" \
        "$static_root/libjimage.a"
}

device_library="$build_root/libdevice.a"
simulator_library="$build_root/libsim.a"
combine_runtime \
    ios-aarch64-zero-release \
    "$device_support/libffi.a" \
    "$device_library"
combine_runtime \
    iossim-aarch64-zero-release \
    "$simulator_libffi_arm64" \
    "$simulator_library"

verify_archive_target() {
    local library="$1"
    local expected_platform="$2"
    local probe_root
    local build_info
    local actual_platform
    local actual_target
    probe_root="$(mktemp -d "$build_root/version-probe.XXXXXX")"
    (
        cd "$probe_root"
        ar -x "$library" abstractCompiler.o
        xcrun vtool -show-build abstractCompiler.o 2>/dev/null
    ) > "$probe_root/build-info"
    build_info="$(<"$probe_root/build-info")"
    actual_platform="$(
        awk '$1 == "platform" { print $2; exit }' <<< "$build_info"
    )"
    actual_target="$(
        awk '$1 == "minos" { print $2; exit }' <<< "$build_info"
    )"
    if [[ "$actual_platform" != "$expected_platform" ]]; then
        echo "$library targets $actual_platform, expected $expected_platform." >&2
        rm -rf "$probe_root"
        exit 1
    fi
    if [[ "$actual_target" != "$deployment_target" ]]; then
        echo "$library targets iOS $actual_target, expected $deployment_target." >&2
        rm -rf "$probe_root"
        exit 1
    fi
    rm -rf "$probe_root"
}

verify_archive_target "$device_library" IOS
verify_archive_target "$simulator_library" IOSSIMULATOR

prepare_headers() {
    local configuration="$1"
    local destination="$2"
    mkdir -p "$destination"
    cp -R "$mobile_root/build/$configuration/jdk/include/." "$destination/"
    if [[ -d "$destination/ios" ]]; then
        cp -R "$destination/ios/." "$destination/"
    fi
}

device_headers="$build_root/device-headers"
simulator_headers="$build_root/simulator-headers"
prepare_headers ios-aarch64-zero-release "$device_headers"
prepare_headers iossim-aarch64-zero-release "$simulator_headers"

framework="$build_root/OpenJDK.xcframework"
xcodebuild -create-xcframework \
    -library "$device_library" \
    -headers "$device_headers" \
    -library "$simulator_library" \
    -headers "$simulator_headers" \
    -output "$framework"

create_java_bundle() {
    local configuration="$1"
    local platform="$2"
    local destination="$3"
    local module_classes="$mobile_root/build/$configuration/jdk/modules/java.base"
    local jmods="$build_root/jmods-$configuration"
    mkdir -p "$jmods"
    "$image_java_home/bin/jmod" create \
        --class-path "$module_classes" \
        --target-platform "$platform" \
        "$jmods/java.base.jmod"
    "$image_java_home/bin/jlink" \
        --module-path "$jmods" \
        --add-modules java.base \
        --output "$destination"
}

device_bundle="$build_root/java_bundle-device"
simulator_bundle="$build_root/java_bundle-simulator"
create_java_bundle ios-aarch64-zero-release ios-aarch64 "$device_bundle"
create_java_bundle iossim-aarch64-zero-release ios-aarch64-simulator "$simulator_bundle"

rm -rf \
    "$vendor_root/OpenJDK.xcframework" \
    "$vendor_root/java_bundle-device" \
    "$vendor_root/java_bundle-simulator"
mkdir -p "$vendor_root"
ditto "$framework" "$vendor_root/OpenJDK.xcframework"
ditto "$device_bundle" "$vendor_root/java_bundle-device"
ditto "$simulator_bundle" "$vendor_root/java_bundle-simulator"
printf '%s\n' "$stamp_value" > "$stamp_file"

echo "Built matching OpenJDK 26 device and simulator runtimes for iOS $deployment_target"
