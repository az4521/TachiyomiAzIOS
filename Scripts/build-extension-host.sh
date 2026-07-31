#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$repository_root/Runtime/ExtensionHost/src/main/java"
test_source_root="$repository_root/Runtime/ExtensionHost/src/test/java"
compat_test_source_root="$repository_root/Runtime/ExtensionHost/src/compatTest/java"
build_root="$repository_root/Runtime/ExtensionHost/build"
classes_root="$build_root/classes"
test_classes_root="$build_root/test-classes"
compat_test_classes_root="$build_root/compat-test-classes"
distribution_root="$repository_root/Runtime/ExtensionHost/dist"
output_jar="$distribution_root/tachiaz-extension-host.jar"

if [[ -n "${TACHIYOMIAZ_BUILD_JAVA_HOME:-}" ]]; then
    java_home="$TACHIYOMIAZ_BUILD_JAVA_HOME"
elif [[ -n "${TACHIAZ_BUILD_JAVA_HOME:-}" ]]; then
    java_home="$TACHIAZ_BUILD_JAVA_HOME"
elif [[ -n "${JAVA_HOME:-}" ]]; then
    java_home="$JAVA_HOME"
else
    echo "Set TACHIYOMIAZ_BUILD_JAVA_HOME or JAVA_HOME to a JDK 8+ installation." >&2
    exit 1
fi

javac="$java_home/bin/javac"
java="$java_home/bin/java"
jar="$java_home/bin/jar"
test_java_home="${TACHIAZ_TEST_JAVA_HOME:-$java_home}"
test_java="$test_java_home/bin/java"
test_java_options=()
if [[ -n "${TACHIAZ_TEST_JAVA_OPTIONS:-}" ]]; then
    read -r -a test_java_options <<< "$TACHIAZ_TEST_JAVA_OPTIONS"
fi

for executable in "$javac" "$java" "$jar" "$test_java"; do
    if [[ ! -x "$executable" ]]; then
        echo "Required Java tool is missing or not executable: $executable" >&2
        exit 1
    fi
done

rm -rf "$build_root" "$distribution_root"
mkdir -p \
    "$classes_root" \
    "$test_classes_root" \
    "$compat_test_classes_root" \
    "$distribution_root"

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

# JAR entry timestamps otherwise make this tracked build artifact change after
# every validation run. ZIP timestamps start in 1980, and BSD/GNU touch both
# accept this fixed form.
find "$classes_root" -exec touch -t 198001010000 {} +
"$jar" cMf "$output_jar" -C "$classes_root" .

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
    "$jar" cf "$fixture_jar" \
        -C "$test_classes_root" fixture \
        -C "$repository_root/Runtime/ExtensionHost/src/test/resources" \
        AndroidManifest.xml

    "$test_java" "${test_java_options[@]}" \
        -cp "$output_jar:$test_classes_root" \
        app.tachiaz.runtime.ExtensionHostTest \
        "$fixture_jar"

    if [[ -n "${TACHIAZ_ASURA_JAR:-}" ]]; then
        "$test_java" "${test_java_options[@]}" \
            -cp "$output_jar:$test_classes_root" \
            app.tachiaz.runtime.TachiyomiXAsuraScansTest \
            "$TACHIAZ_ASURA_JAR"
    fi

    if [[ -n "${TACHIAZ_COMPAT_CLASSPATH:-}" ]]; then
        mapfile -t compat_test_sources < <(
            find "$compat_test_source_root" -name '*.java' -type f | sort
        )
        "$javac" \
            -source 8 \
            -target 8 \
            -encoding UTF-8 \
            -cp "$TACHIAZ_COMPAT_CLASSPATH:$output_jar" \
            -d "$compat_test_classes_root" \
            "${compat_test_sources[@]}"

        "$test_java" "${test_java_options[@]}" \
            -cp \
            "$TACHIAZ_COMPAT_CLASSPATH:$output_jar:$compat_test_classes_root" \
            app.tachiaz.runtime.MihonExtensionLib16FallbackTest

        if [[ "${TACHIAZ_VERIFY_MOBILE_SHIMS:-}" == "1" ]]; then
            "$test_java" "${test_java_options[@]}" \
                -cp \
                "$TACHIAZ_COMPAT_CLASSPATH:$output_jar:$compat_test_classes_root" \
                app.tachiaz.runtime.MobileShimPrecedenceTest
        fi

        if [[ -n "${TACHIAZ_MIHON_14_JAR:-}" ]]; then
            "$test_java" "${test_java_options[@]}" \
                -cp \
                "$TACHIAZ_COMPAT_CLASSPATH:$output_jar:$compat_test_classes_root" \
                app.tachiaz.runtime.MihonExtensionLib14RuntimeTest \
                "$TACHIAZ_MIHON_14_JAR"
        fi

        if [[ -n "${TACHIAZ_MANGADEX_JAR:-}" ]]; then
            "$test_java" "${test_java_options[@]}" \
                -cp \
                "$TACHIAZ_COMPAT_CLASSPATH:$output_jar:$test_classes_root" \
                app.tachiaz.runtime.TachiyomiXMangaDexRuntimeTest \
                "$TACHIAZ_MANGADEX_JAR"
        fi

        if [[ -n "${TACHIAZ_ASURA_JAR:-}" ]]; then
            "$test_java" "${test_java_options[@]}" \
                -cp "$TACHIAZ_COMPAT_CLASSPATH:$output_jar:$test_classes_root" \
                app.tachiaz.runtime.TachiyomiXAsuraRuntimeTest \
                "$TACHIAZ_ASURA_JAR"
        fi
    fi
fi

echo "$output_jar"
