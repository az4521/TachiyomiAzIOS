#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${TMPDIR:-/tmp}/tachiaz-keiyoushi-fixtures"
fixture_name="tachiyomi-en.asurascans-v1.6.66.jar"
fixture_path="$fixture_root/$fixture_name"
fixture_url="https://raw.githubusercontent.com/keiyoushi/extensions/repo/jar/$fixture_name"
expected_sha256="ce8d03b408a6b329b02f9b2c9280badb981ff352703a45749a443f87805c46ff"

if [[ -n "${1:-}" ]]; then
    fixture_path="$1"
else
    command -v curl >/dev/null || {
        echo "curl is required to download the Asura Scans fixture." >&2
        exit 1
    }
    mkdir -p "$fixture_root"
    if [[ ! -f "$fixture_path" ]]; then
        curl --fail --location --output "$fixture_path" "$fixture_url"
    fi
fi

if command -v shasum >/dev/null; then
    actual_sha256="$(shasum -a 256 "$fixture_path" | cut -d ' ' -f 1)"
elif command -v sha256sum >/dev/null; then
    actual_sha256="$(sha256sum "$fixture_path" | cut -d ' ' -f 1)"
else
    echo "shasum or sha256sum is required." >&2
    exit 1
fi

if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Asura Scans fixture checksum mismatch." >&2
    echo "Expected: $expected_sha256" >&2
    echo "Actual:   $actual_sha256" >&2
    exit 1
fi

TACHIAZ_ASURA_JAR="$fixture_path" \
    "$repository_root/Scripts/build-extension-host.sh" --test
