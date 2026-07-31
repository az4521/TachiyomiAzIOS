#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_root="$repository_root/Vendor/OpenJDK"
archive_path="${TMPDIR:-/tmp}/tachiaz-openjdk-ios.zip"
release_url="https://github.com/thebaselab/android-openjdk-build-multiarch/releases/download/v0.2/java-8-zero-frameworks-tools-with-src.zip"
expected_sha256="da58bb27f5b214d3c2e6795d47a625fbc1ea862e318124a9f04f13bc609d0457"

command -v curl >/dev/null || {
    echo "curl is required." >&2
    exit 1
}
command -v unzip >/dev/null || {
    echo "unzip is required." >&2
    exit 1
}
mkdir -p "$vendor_root"

if [[ ! -f "$archive_path" ]]; then
    curl --fail --location --output "$archive_path" "$release_url"
fi

if command -v shasum >/dev/null; then
    actual_sha256="$(shasum -a 256 "$archive_path" | cut -d ' ' -f 1)"
elif command -v sha256sum >/dev/null; then
    actual_sha256="$(sha256sum "$archive_path" | cut -d ' ' -f 1)"
else
    echo "shasum or sha256sum is required." >&2
    exit 1
fi
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "OpenJDK archive checksum mismatch." >&2
    echo "Expected: $expected_sha256" >&2
    echo "Actual:   $actual_sha256" >&2
    exit 1
fi

rm -rf "$vendor_root/java-8-openjdk" "$vendor_root/java-frameworks"
unzip -q "$archive_path" -d "$vendor_root"

if [[ ! -d "$vendor_root/java-8-openjdk" || ! -d "$vendor_root/java-frameworks" ]]; then
    echo "Downloaded archive did not contain the expected runtime directories." >&2
    exit 1
fi

echo "OpenJDK Zero runtime installed under $vendor_root"
