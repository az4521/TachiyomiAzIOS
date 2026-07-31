#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$repository_root/Runtime/MobileShims/src/main/java"
build_root="$repository_root/Runtime/MobileShims/build"
output_root="$repository_root/Runtime/MobileShims/dist"
output_jar="$output_root/tachiaz-mobile-shims.jar"
output_cacerts="$output_root/cacerts"

if [[ -n "${TACHIAZ_BUILD_JAVA_HOME:-}" ]]; then
    java_home="$TACHIAZ_BUILD_JAVA_HOME"
elif [[ -n "${JAVA_HOME:-}" ]]; then
    java_home="$JAVA_HOME"
else
    echo "Set TACHIAZ_BUILD_JAVA_HOME or JAVA_HOME." >&2
    exit 1
fi

rm -rf "$build_root" "$output_root"
mkdir -p "$build_root" "$output_root"
mapfile -t sources < <(find "$source_root" -name '*.java' -type f | sort)

"$java_home/bin/javac" \
    -source 8 \
    -target 8 \
    -encoding UTF-8 \
    -d "$build_root" \
    "${sources[@]}"
find "$build_root" -exec touch -t 198001010000 {} +
"$java_home/bin/jar" cMf "$output_jar" -C "$build_root" .
if [[ ! -f "$java_home/lib/security/cacerts" ]]; then
    echo "JDK trust store is missing: $java_home/lib/security/cacerts" >&2
    exit 1
fi
cp "$java_home/lib/security/cacerts" "$output_cacerts"

echo "$output_jar"
