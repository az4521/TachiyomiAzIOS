#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${TMPDIR:-/tmp}/tachiaz-tachiyomix-fixtures"
fixture_name="tachiyomix-extension-lib-1_6-fixture.jar"
fixture_path="$fixture_root/$fixture_name"
fixture_url="${TACHIYOMIAZ_EXTLIB_1_6_FIXTURE_URL:-${TACHIAZ_EXTLIB_1_6_FIXTURE_URL:-}}"
expected_sha256="ce8d03b408a6b329b02f9b2c9280badb981ff352703a45749a443f87805c46ff"
compatibility_root="$repository_root/Runtime/ExtensionHost/compat"

if [[ -n "${1:-}" ]]; then
    fixture_path="$1"
else
    command -v curl >/dev/null || {
        echo "curl is required to download the extension-lib 1.6 fixture." >&2
        exit 1
    }
    mkdir -p "$fixture_root"
    if [[ ! -f "$fixture_path" ]]; then
        if [[ -z "$fixture_url" ]]; then
            echo "Pass the extension-lib 1.6 JAR path or set TACHIYOMIAZ_EXTLIB_1_6_FIXTURE_URL." >&2
            exit 1
        fi
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
    echo "Extension-lib 1.6 fixture checksum mismatch." >&2
    echo "Expected: $expected_sha256" >&2
    echo "Actual:   $actual_sha256" >&2
    exit 1
fi

compatibility_jars=()
while IFS= read -r compatibility_jar; do
    compatibility_jars+=("$compatibility_jar")
done < <(
    find "$compatibility_root" -name '*.jar' -type f | sort
)
if [[ "${#compatibility_jars[@]}" -eq 0 ]]; then
    echo "Suwayomi compatibility JARs are missing." >&2
    echo "Run Scripts/bootstrap-suwayomi-compat.sh first." >&2
    exit 1
fi
compatibility_classpath="$(
    IFS=:
    echo "${compatibility_jars[*]}"
)"

TACHIAZ_EXTLIB_1_6_JAR="$fixture_path" \
TACHIAZ_COMPAT_CLASSPATH="$compatibility_classpath" \
    "$repository_root/Scripts/build-extension-host.sh" --test
