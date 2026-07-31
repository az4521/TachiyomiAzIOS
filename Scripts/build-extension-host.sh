#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$repository_root/Runtime/ExtensionHost/src/main/java"
test_source_root="$repository_root/Runtime/ExtensionHost/src/test/java"
build_root="$repository_root/Runtime/ExtensionHost/build"
classes_root="$build_root/classes"
test_classes_root="$build_root/test-classes"
distribution_root="$repository_root/Runtime/ExtensionHost/dist"
output_jar="$distribution_root/tachiaz-extension-host.jar"

if [[ -n "${TACHIAZ_BUILD_JAVA_HOME:-}" ]]; then
    java_home="$TACHIAZ_BUILD_JAVA_HOME"
elif [[ -n "${JAVA_HOME:-}" ]]; then
    java_home="$JAVA_HOME"
else
    echo "Set TACHIAZ_BUILD_JAVA_HOME or JAVA_HOME to a JDK 8+ installation." >&2
    exit 1
fi

javac="$java_home/bin/javac"
java="$java_home/bin/java"
jar="$java_home/bin/jar"

for executable in "$javac" "$java" "$jar"; do
    if [[ ! -x "$executable" ]]; then
        echo "Required Java tool is missing or not executable: $executable" >&2
        exit 1
    fi
done

rm -rf "$build_root" "$distribution_root"
mkdir -p "$classes_root" "$test_classes_root" "$distribution_root"

mapfile -t main_sources < <(find "$source_root" -name '*.java' -type f | sort)
if [[ "${#main_sources[@]}" -eq 0 ]]; then
    echo "No ExtensionHost Java sources found under $source_root" >&2
    exit 1
fi

"$javac" \
    -source 8 \
    -target 8 \
    -encoding UTF-8 \
    -d "$classes_root" \
    "${main_sources[@]}"

"$jar" cf "$output_jar" -C "$classes_root" .

if [[ "${1:-}" == "--test" ]]; then
    mapfile -t test_sources < <(find "$test_source_root" -name '*.java' -type f | sort)
    if [[ "${#test_sources[@]}" -eq 0 ]]; then
        echo "No ExtensionHost tests found under $test_source_root" >&2
        exit 1
    fi

    "$javac" \
        -source 8 \
        -target 8 \
        -encoding UTF-8 \
        -cp "$output_jar" \
        -d "$test_classes_root" \
        "${test_sources[@]}"

    fixture_jar="$build_root/fixture-extension.jar"
    "$jar" cf "$fixture_jar" -C "$test_classes_root" fixture

    "$java" \
        -cp "$output_jar:$test_classes_root" \
        app.tachiaz.runtime.ExtensionHostTest \
        "$fixture_jar"
fi

echo "$output_jar"
