#!/usr/bin/env bash
set -euo pipefail

repository_url='github.com/Aidoku/'"AidokuRunner"
if git grep -n -F "${repository_url}" -- \
    Aidoku.xcodeproj \
    Packages \
    Shared \
    iOS \
    macOS
then
    echo "External AidokuRunner dependency found." >&2
    exit 1
fi

if git grep -n -F 'XCRemoteSwiftPackageReference "AidokuRunner"' -- \
    Aidoku.xcodeproj/project.pbxproj
then
    echo "Remote AidokuRunner Xcode package reference found." >&2
    exit 1
fi

echo "External AidokuRunner dependency is absent."
