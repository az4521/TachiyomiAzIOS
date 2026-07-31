# Implementation status

Last updated: 2026-07-31

## Implemented

- Local `TachiJVMRunner` Swift package with a C++ JNI boundary.
- One persistent official OpenJDK/mobile Zero VM, with thread attach/detach and real UTF-8
  request/response conversion.
- Checksum-pinned OpenJDK/mobile XCFramework and device class-library bootstrap.
- Xcode device integration for the static VM XCFramework and Java bundle.
- Runtime-aware bytecode validation before an extension JAR is loaded.
- Keiyoushi textual Android manifest parsing and automatic entry-class
  discovery, without `dex2jar` or APK conversion.
- Keiyoushi `/repo/jar` URL mapping from index `.apk` basenames to direct
  `.jar` artifacts, with a pinned Asura Scans fixture.
- Per-extension `URLClassLoader` lifecycle and a stable JSON dispatch entry
  point.
- SHA-256-verifying Swift JAR installer and versioned extension storage.
- Java host integration tests for loading, invoking, replacing, and unloading
  a fixture extension.
- A pinned real-world test against Keiyoushi's
  `tachiyomi-en.asurascans-v1.6.66.jar` and its published SHA-256.
- Initial dependency-free Android compatibility classes for `Uri`, `Base64`,
  logging, and Android version/device checks.
- Gzipped protobuf decoding for current Mihon and TachiyomiAZ `.tachibk`
  backups.
- Conversion of manga, library membership, categories, chapters, read
  progress, history, source IDs, and viewer settings into Aidoku's backup
  model.
- `.tachibk` and legacy `.proto.gz` selection and deep-link import.
- Material Design 1-inspired hamburger drawer using the existing Aidoku
  library, browse, history, search, and settings controllers.

## Compatibility transition

AidokuRunner remains linked temporarily. It keeps the app's existing sources
usable while the Mihon `Source`/`HttpSource` and Android compatibility APIs are
implemented. The JVM path is already independent of AidokuRunner; removing the
old package today would leave no production-ready online source until the next
item is complete.

## Required before calling the fork complete

1. Build a binary-compatible host implementation of Keiyoushi extension-lib
   1.6 and the Mihon extension API,
   including `Source`, `SourceFactory`, `HttpSource`, models, filters, RxJava,
   OkHttp, and Jsoup integration.
2. Finish the AndroidCompat subset. URI, Base64, logging, and build/version
   checks exist; context, preferences, resources, cookies, and required
   graphics behavior remain.
3. Implement repository catalog/update UX over Keiyoushi-style index metadata,
   deriving direct `/jar/*.jar` artifact URLs and persisting checksums.
4. Add typed JNI operations for popular/latest/search, manga details, chapter
   lists, pages, filters, preferences, and cookies.
5. Feed JVM source results into Aidoku's `Source` abstraction, migrate stored
   source keys, then remove AidokuRunner/WASM and delegated-source code.
6. Preserve bookmarks and supported tracking records during backup import;
   they currently have no lossless one-to-one mapping in Aidoku's backup model.
7. Validate launch, networking, TLS, memory pressure, backgrounding, JAR
   loading, and backup restore on a physical arm64 iPhone/iPad.

## Validation completed in this workspace

- Extension host compiles with Temurin JDK 8 using `-source 8 -target 8`.
- Fixture JAR load/invoke/unload test passes.
- Gzipped Mihon protobuf fixture decode test passes.
- The pinned Asura Scans 1.6.66 JAR is downloaded, checksum-verified, inspected,
  and confirmed as Java 11 / class-file version 55 with the expected
  `ExtensionGenerated` entry point.
- JNI C++ bridge compiles with `-std=c++17 -Wall -Wextra -Werror`.
- Git whitespace checks pass.

Xcode, Swift, and an iOS SDK are not installed in the current Linux/WSL
workspace, so an honest Xcode compile or device-runtime claim cannot be made
here.
