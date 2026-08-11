#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$repository_root/Vendor/OpenJDK/OpenJDK.xcframework/ios-arm64/libdevice.a"
destination="$repository_root/iOS/JVM/OpenJDK.exports"
temporary="$(mktemp "${TMPDIR:-/tmp}/tachiyomiaz-openjdk-exports.XXXXXX")"
trap 'rm -f "$temporary"' EXIT

if [[ ! -f "$archive" ]]; then
    echo "OpenJDK device archive is missing: $archive" >&2
    exit 1
fi

if command -v xcrun >/dev/null 2>&1; then
    xcrun nm -gjU "$archive"
elif command -v llvm-nm >/dev/null 2>&1; then
    llvm-nm -g --defined-only "$archive" | awk '{ print $3 }'
elif [[ -x /usr/lib/llvm-19/bin/llvm-nm ]]; then
    /usr/lib/llvm-19/bin/llvm-nm -g --defined-only "$archive" |
        awk '{ print $3 }'
else
    echo "An nm implementation capable of reading Mach-O archives is required." >&2
    exit 1
fi |
    awk '/^_(Java_|JVM_|JNI_|JIMAGE_|JDK_Canonicalize$|VerifyClassCodes(ForMajorVersion)?$|ZIP_|JNU_|GetStringPlatformChars$)/' |
    LC_ALL=C sort -u > "$temporary"

if [[ ! -s "$temporary" ]]; then
    echo "No statically linked JVM exports were found in $archive." >&2
    exit 1
fi

mv "$temporary" "$destination"
trap - EXIT
echo "Generated $(wc -l < "$destination" | tr -d ' ') JVM exports at $destination"
