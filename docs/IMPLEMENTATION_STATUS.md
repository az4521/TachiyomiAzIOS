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
- A reproducible compatibility bootstrap pinned to Suwayomi-Server commit
  `eb2dc0b19a9571b27c02bebc5c883e404b7bd7fb`, using its AndroidCompat and
  Mihon source implementations.
- Reflective Koin/AndroidCompat initialization before extension construction.
- Direct coroutine invocation and typed Swift DTOs for popular manga pages.
- Manifest gating for the supported Mihon extension-lib 1.4–1.6 range.
- A binary fixture compiled against official TachiyomiX 1.4.4 that proves a
  suspend host call falls back to its Rx-only popular implementation.
- A live Asura Scans test that constructs the extension and fetches page 1
  from its public API without APK conversion or `dex2jar`.
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

1. Reduce and audit the currently generated ~57 MB Suwayomi compatibility
   classpath further, while retaining binary compatibility across a broader
   extension fixture matrix.
2. Validate AndroidCompat behavior needed beyond Asura: resources, graphics,
   WebView/Cloudflare challenges, JavaScript, and persistence on iOS.
3. Implement repository catalog/update UX over Keiyoushi-style index metadata,
   deriving direct `/jar/*.jar` artifact URLs and persisting checksums.
4. Add typed JNI operations for latest/search, manga details, chapter lists,
   pages, filters, preferences, and cookies. Popular manga is implemented.
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
- The pinned Suwayomi source API and AndroidCompat build successfully on
  JDK 21.
- Asura Scans constructs through the real compatibility layer and reports the
  expected name, language, source ID, and base URL.
- Its coroutine popular-manga method reaches
  `https://api.asurascans.com/api/series`, returns HTTP 200, and decodes 20
  typed manga summaries with `hasNextPage = true`.
- JNI C++ bridge compiles with `-std=c++17 -Wall -Wextra -Werror`.
- Git whitespace checks pass.

Xcode, Swift, and an iOS SDK are not installed in the current Linux/WSL
workspace, so an honest Xcode compile or device-runtime claim cannot be made
here.
