#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_root="${TMPDIR:-/tmp}/tachiaz-java-base-probe"
shims="$repository_root/Runtime/MobileShims/dist/tachiaz-mobile-shims.jar"

if [[ -n "${TACHIYOMIAZ_BUILD_JAVA_HOME:-}" ]]; then
    java_home="$TACHIYOMIAZ_BUILD_JAVA_HOME"
elif [[ -n "${TACHIAZ_BUILD_JAVA_HOME:-}" ]]; then
    java_home="$TACHIAZ_BUILD_JAVA_HOME"
elif [[ -n "${JAVA_HOME:-}" ]]; then
    java_home="$JAVA_HOME"
else
    echo "Set TACHIYOMIAZ_BUILD_JAVA_HOME or JAVA_HOME." >&2
    exit 1
fi

rm -rf "$probe_root"
"$java_home/bin/jlink" \
    --add-modules java.base,jdk.crypto.ec,jdk.unsupported \
    --output "$probe_root" \
    --strip-debug \
    --no-header-files \
    --no-man-pages

TACHIYOMIAZ_BUILD_JAVA_HOME="$java_home" \
    "$repository_root/Scripts/build-mobile-shims.sh"

TACHIYOMIAZ_BUILD_JAVA_HOME="$java_home" \
TACHIAZ_TEST_JAVA_HOME="$probe_root" \
TACHIAZ_TEST_JAVA_OPTIONS="-Xbootclasspath/a:$shims" \
TACHIAZ_VERIFY_MOBILE_SHIMS=1 \
    "$repository_root/Scripts/test-tachiyomix-1_4.sh"

TACHIYOMIAZ_BUILD_JAVA_HOME="$java_home" \
TACHIAZ_TEST_JAVA_HOME="$probe_root" \
TACHIAZ_TEST_JAVA_OPTIONS="-Xbootclasspath/a:$shims" \
TACHIAZ_VERIFY_MOBILE_SHIMS=1 \
    "$repository_root/Scripts/test-tachiyomix-1_6.sh"

echo "java.base-style extension-lib 1.4 and 1.6 tests passed"
