# Implementation status

Last updated: 2026-07-31

## Implemented

- Local `TachiJVMRunner` Swift package with a C++ JNI boundary.
- One persistent official OpenJDK/mobile Zero VM, with thread attach/detach and real UTF-8
  request/response conversion.
- Checksum-pinned OpenJDK/mobile XCFramework plus device and simulator
  class-library bootstrap.
- Xcode integration for the static VM on arm64 devices and arm64/x86_64 iOS
  simulators, embedding the destination-specific Java bundle.
- Runtime-aware bytecode validation before an extension JAR is loaded.
- Keiyoushi textual Android manifest parsing and automatic entry-class
  discovery, without `dex2jar` or APK conversion.
- Keiyoushi `/repo/jar` URL mapping from index `.apk` basenames to direct
  `.jar` artifacts, with a pinned Asura Scans fixture.
- Per-extension `URLClassLoader` lifecycle and a stable JSON dispatch entry
  point.
- SHA-256-verifying Swift JAR installer and versioned extension storage.
- Transactional JAR replacement: a candidate is constructed under a temporary
  host id before its files replace the installed version, with rollback on a
  failed final load.
- Java host integration tests for loading, invoking, replacing, and unloading
  a fixture extension.
- A pinned real-world test against Keiyoushi's
  `tachiyomi-en.asurascans-v1.6.66.jar` and its published SHA-256.
- A reproducible compatibility bootstrap pinned to Suwayomi-Server commit
  `eb2dc0b19a9571b27c02bebc5c883e404b7bd7fb`, using its AndroidCompat and
  Mihon source implementations.
- Reflective Koin/AndroidCompat initialization before extension construction.
- Direct coroutine invocation and typed Swift DTOs for popular manga pages.
- Typed latest, search, combined manga-details/chapter, and page-list
  operations, with suspend-to-Rx fallback supplied by Mihon's source API.
- First-class Aidoku `Runner` adapters for installed Mihon source IDs, mapping
  browse/search/details/chapters/pages into the existing library, download,
  and reader models.
- Keiyoushi's extension-lib 1.6 `index.json` catalog, direct JAR
  download/identity verification, installation, update detection, persisted
  discovery, and uninstall support.
- In-app searchable Keiyoushi extension catalog with icons, languages, NSFW
  labeling, install progress, and update actions.
- Dynamic Mihon filter discovery and state application for text, checkbox,
  tri-state, select, grouped, and sort filters.
- AndroidX extension preference discovery and persisted editing for switches,
  text, single-select, and multi-select values.
- Native reader image requests reconstructed through each extension's
  `imageRequest`, including source headers and persistent Java cookies.
- JVM home and temporary paths explicitly rooted inside the app container so
  AndroidCompat preferences and cookies persist on simulator and device.
- Source cookie inspection/clearing and an Aidoku WKWebView login flow that
  transfers login and Cloudflare cookies into the extension's OkHttp jar.
- An iOS-safe `SystemClock` plus a minimal JUL boot shim for OkHttp/Okio,
  removing runtime dependencies on absent `java.logging` and
  `java.management` modules.
- A regression test proving `SystemClock` alone comes from the mobile boot
  shim while the complete AndroidCompat API remains ahead of host fixtures.
- A bundled CA trust store for TLS; the upstream OpenJDK/mobile snapshot only
  contains its `java.base` jimage.
- Manifest gating for the supported Mihon extension-lib 1.4–1.6 range.
- A binary fixture compiled against official TachiyomiX 1.4.4 that proves a
  suspend host call falls back to its Rx-only popular implementation.
- `SourceFactory` expansion, source enumeration, and source-ID routing, tested
  against the 61-source Keiyoushi MangaDex 1.4.211 extension.
- A live MangaDex 1.4 test that selects its English source and fetches page 1
  through Mihon's suspend-to-Rx compatibility fallback.
- A live Asura Scans test that constructs the extension and fetches page 1
  from its public API without APK conversion or `dex2jar`.
- Gzipped protobuf decoding for current Mihon and TachiyomiAZ `.tachibk`
  backups.
- Conversion of manga, library membership, categories, chapters, chapter
  bookmarks, read progress, history, source IDs, supported tracker links, and
  correctly translated viewer settings into Aidoku's backup model.
- Regression coverage for Mihon's extra publication states and TachiyomiAZ's
  id-less category/order format and extended reader modes.
- `.tachibk` and legacy `.proto.gz` selection and deep-link import, including
  first-class `.tachibk` document registration and `tachiaz://` URLs.
- Material Design 1-inspired hamburger drawer using the existing Aidoku
  library, browse, history, search, and settings controllers.

## Compatibility transition

AidokuRunner remains linked for the shared manga/chapter/filter/setting models
and `Runner` protocol used throughout Aidoku's UI. Keiyoushi sources do not use
its WASM interpreter. The old AIX/WASM installation path remains available only
as a compatibility fallback until a macOS Xcode build confirms it can be
removed without stranding local or self-hosted source adapters.

## Required before calling the fork complete

1. Run the configured Xcode build for a generic arm64/x86_64 iOS Simulator on
   a macOS host. This workspace has no Xcode or iOS SDK.
2. Validate Android graphics/resource edge cases across a broader extension
   fixture matrix. JavaScript/login challenges use the native WKWebView flow;
   desktop CEF is deliberately excluded.
3. Remove the old WASM interpreter and AIX/delegated-source installation path
   after the Xcode build confirms there are no remaining UI-only dependencies.

Physical arm64 device validation remains desirable, but it is not a blocker
for the simulator-first sideloading target.

## Validation completed in this workspace

- Extension host compiles with Temurin JDK 8 using `-source 8 -target 8`.
- Fixture JAR load/invoke/unload test passes.
- Gzipped Mihon protobuf fixture decode test passes.
- The pinned MangaDex 1.4.211 and Asura Scans 1.6.66 JARs are downloaded and
  checksum-verified. Asura is confirmed as Java 11 / class-file version 55.
- The pinned Suwayomi source API and AndroidCompat build successfully on
  JDK 21.
- A minimal `java.base` + EC-crypto runtime probe, using the same boot shim as
  iOS and no desktop Logback provider, completes every MangaDex 1.4 and Asura
  Scans 1.6 integration operation.
- Asura Scans constructs through the real compatibility layer and reports the
  expected name, language, source ID, and base URL.
- MangaDex constructs all 61 sources from `ExtensionGenerated`, selects source
  ID `2499283573021220255` (`en`), reaches `https://api.mangadex.org`, returns
  HTTP 200, and completes popular, latest, search, details, chapter-list, and
  page-list operations through the extension-lib 1.4 fallback path.
- MangaDex filter descriptors are projected into native filter controls; a
  sort-state round trip changes its live API request to title/ascending.
- MangaDex AndroidX preferences are discovered and a select preference is
  written back through its persistent `SharedPreferences`.
- WKWebView-style cookies can be inserted into MangaDex's real persistent
  OkHttp cookie jar, inspected without exposing values, and cleared.
- MangaDex page context survives the JNI boundary and reconstructs the
  extension-specific image request, headers, and cookie jar for Aidoku's
  native image pipeline.
- Its coroutine popular-manga method reaches
  `https://api.asurascans.com/api/series`, returns HTTP 200, and decodes 20
  typed manga summaries with `hasNextPage = true`.
- JNI C++ bridge compiles with `-std=c++17 -Wall -Wextra -Werror`.
- Git whitespace checks pass.
- The nightly macOS job compiles both the app and its unit-test bundle for a
  generic arm64/x86_64 iOS Simulator before producing the device archive.

Xcode, Swift, and an iOS SDK are not installed in the current Linux/WSL
workspace, so an honest Xcode compile or device-runtime claim cannot be made
here.
