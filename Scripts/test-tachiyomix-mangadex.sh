#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${TMPDIR:-/tmp}/tachiaz-tachiyomix-fixtures"
fixture_name="tachiyomi-all.mangadex-v1.4.211.jar"
fixture_path="$fixture_root/$fixture_name"
fixture_url="${TACHIYOMIAZ_MANGADEX_FIXTURE_URL:-${TACHIAZ_MANGADEX_FIXTURE_URL:-}}"
expected_sha256="401158e4d00e111998c20243adbddf64b377b95191d1e14d054b1a1a038c51e9"
compatibility_root="$repository_root/Runtime/ExtensionHost/compat"

if [[ -n "${1:-}" ]]; then
    fixture_path="$1"
else
    command -v curl >/dev/null || {
        echo "curl is required to download the MangaDex fixture." >&2
        exit 1
    }
    mkdir -p "$fixture_root"
    if [[ ! -f "$fixture_path" ]]; then
        if [[ -z "$fixture_url" ]]; then
            echo "Pass the MangaDex extension JAR path or set TACHIYOMIAZ_MANGADEX_FIXTURE_URL." >&2
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
    echo "MangaDex fixture checksum mismatch." >&2
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
compatibility_classpath="$(
    IFS=:
    echo "${compatibility_jars[*]}"
)"

TACHIAZ_COMPAT_CLASSPATH="$compatibility_classpath" \
TACHIAZ_MANGADEX_JAR="$fixture_path" \
    "$repository_root/Scripts/build-extension-host.sh" --test
