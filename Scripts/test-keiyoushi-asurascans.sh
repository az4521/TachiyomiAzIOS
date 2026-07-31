#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${TMPDIR:-/tmp}/tachiaz-keiyoushi-fixtures"
fixture_name="tachiyomi-en.asurascans-v1.6.66.jar"
fixture_path="$fixture_root/$fixture_name"
fixture_url="https://raw.githubusercontent.com/keiyoushi/extensions/repo/jar/$fixture_name"
expected_sha256="ce8d03b408a6b329b02f9b2c9280badb981ff352703a45749a443f87805c46ff"
compatibility_root="$repository_root/Runtime/ExtensionHost/compat"
mihon_14_fixture="$repository_root/Runtime/ExtensionHost/fixtures/mihon-1.4/mihon-extension-lib-1.4-fixture.jar"

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

mapfile -t compatibility_jars < <(
    find "$compatibility_root" -name '*.jar' -type f | sort
)
if [[ "${#compatibility_jars[@]}" -eq 0 ]]; then
    echo "Suwayomi compatibility JARs are missing." >&2
    echo "Run Scripts/bootstrap-suwayomi-compat.sh first." >&2
    exit 1
fi
if [[ ! -f "$mihon_14_fixture" ]]; then
    echo "Mihon extension-lib 1.4 fixture is missing." >&2
    exit 1
fi
compatibility_classpath="$(
    IFS=:
    echo "${compatibility_jars[*]}"
)"

TACHIAZ_ASURA_JAR="$fixture_path" \
TACHIAZ_COMPAT_CLASSPATH="$compatibility_classpath" \
TACHIAZ_MIHON_14_JAR="$mihon_14_fixture" \
    "$repository_root/Scripts/build-extension-host.sh" --test
