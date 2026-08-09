# Implementation status

Last updated: 2026-07-31

## Implemented

- Local `TachiJVMRunner` Swift package with a C++ JNI boundary.
- One persistent official OpenJDK/mobile Zero VM, with thread attach/detach and real UTF-8
  request/response conversion.
- Revision-pinned OpenJDK/mobile 26 XCFramework plus matching device and
  simulator class-library images, compiled with an iOS 15 target.
- Xcode integration for the static VM on arm64 devices and Apple Silicon arm64
  iOS simulators, embedding the destination-specific Java bundle.
- Runtime-aware bytecode validation before an extension JAR is loaded.
- TachiyomiX textual Android manifest parsing and automatic entry-class
  discovery, without `dex2jar` or APK conversion.
- TachiyomiX `/repo/jar` URL mapping from index `.apk` basenames to direct
  `.jar` artifacts, with a pinned extension-lib 1.6 fixture.
- Per-extension `URLClassLoader` lifecycle and a stable JSON dispatch entry
  point.
- SHA-256-verifying Swift JAR installer and versioned extension storage.
- Catalog health checks expose corrupted installed JARs as repairable instead
  of disabling their reinstall action.
- Transactional JAR replacement: a candidate is constructed under a temporary
  host id before its files replace the installed version, with rollback on a
  failed final load.
- Java host integration tests for loading, invoking, replacing, and unloading
  a fixture extension.
- A pinned real-world extension-lib 1.6 test and published SHA-256.
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
- User-configured current `index.pb` protobuf and equivalent `index.json`
  repositories, direct JAR
  download/identity verification, installation, update detection, persisted
  discovery, and uninstall support. A new install has no configured repository
  and the app embeds no repository URL.
- In-app searchable extension catalogs with icons, languages, NSFW labeling,
  install progress, and update actions. Repository URLs are validated before
  being persisted and can be removed by the user.
- Confirmation-gated `mihon://extension-store?url=…`,
  `tachiyomi://add-repo?url=…`, and
  `tachiyomiaz://extension-store?url=…` repository import links. Legacy
  repository data formats themselves are intentionally unsupported.
- Dynamic Mihon filter discovery and state application for text, checkbox,
  tri-state, select, grouped, and sort filters.
- Opaque extension `memo` JSON round-trips for manga and chapters and is
  persisted in Core Data across app launches.
- AndroidX extension preference discovery and persisted editing for switches,
  text, single-select, and multi-select values.
- Native reader image requests reconstructed through each extension's
  `imageRequest`, including source headers and persistent Java cookies.
- JVM home and temporary paths explicitly rooted inside the app container so
  AndroidCompat preferences and cookies persist on simulator and device.
- Source cookie inspection/clearing and a native WKWebView login flow that
  transfers login and Cloudflare cookies into the extension's OkHttp jar.
- The mobile runtime supplies the Suwayomi `ServerConfigKt`/`ServerConfig`
  ABI used by its Cloudflare interceptor. FlareSolverr is reported as disabled
  so challenges fall through to the app's native WKWebView solver.
- A persisted Advanced setting controls the extension network client's default
  user agent. Cached `HttpSource` defaults update in place while user agents
  explicitly supplied by an extension remain unchanged.
- AndroidCompat's `WebView` and `CookieManager` are backed by WKWebView and
  `WKHTTPCookieStore` on iOS. Navigation is asynchronous so the Android main
  Looper remains available for coroutine timeouts and polling. Page lifecycle,
  modern errors, render termination, console messages, JavaScript evaluation
  and annotated JavaScript interfaces, main-navigation interception, scripted
  fetch interception, history, settings, and cookie mutation cross a reverse
  JNI event channel. WebKit cookies synchronize with `HTTPCookieStorage`, while
  HTML loaded with a base origin is seeded with the matching browser cookies.
  Cloudflare verification is presented immediately with a real device viewport.
  Clearance cookies are copied into the requesting extension's OkHttp cookie
  jar, and that client is pinned to the exact WebKit user agent that issued the
  cookie before retry. Desktop KCEF/JCEF is not bundled.
- An iOS-safe `SystemClock` plus a minimal JUL boot shim for OkHttp/Okio,
  removing runtime dependencies on absent `java.logging` and
  `java.management` modules.
- A regression test proving `SystemClock` alone comes from the mobile boot
  shim while the complete AndroidCompat API remains ahead of host fixtures.
- A bundled CA trust store for TLS; the upstream OpenJDK/mobile snapshot only
  contains its `java.base` jimage.
- Manifest gating for the supported Mihon extension-lib 1.4–1.6 range.
- Unit coverage accepts 1.4, 1.5, and 1.6 (including patch components) while
  rejecting versions outside that range.
- A binary fixture compiled against official TachiyomiX 1.4.4 that proves a
  suspend host call falls back to its Rx-only popular implementation.
- `SourceFactory` expansion, source enumeration, and source-ID routing, tested
  against the 61-source extension-lib 1.4 fixture.
- A live extension-lib 1.4 test that selects its English source and fetches page 1
  through Mihon's suspend-to-Rx compatibility fallback.
- A live extension-lib 1.6 test that constructs the extension and fetches page 1
  from its public API without APK conversion or `dex2jar`.
- Gzipped protobuf decoding for current Mihon and TachiyomiAZ `.tachibk`
  backups.
- Conversion of manga, library membership, categories, chapters, chapter
  bookmarks, read progress, history, source IDs, supported tracker links, and
  correctly translated viewer settings into Aidoku's backup model.
- Regression coverage for Mihon's extra publication states and TachiyomiAZ's
  id-less category/order format, zero-based reading progress, and extended
  reader modes.
- `.tachibk` and legacy `.proto.gz` selection and deep-link import, including
  first-class `.tachibk` document registration and `tachiyomiaz://` URLs
  (`tachiaz://` remains accepted for compatibility).
- Material Design 1-inspired hamburger drawer using the existing Aidoku
  library, browse, history, search, and settings controllers.
- The iOS AIX/WASM importer, installed-interpreter reload path, delegated
  source-list bootstrap/settings, and source-list backup restore are disabled
  after TachiyomiX parity. Local files, Komga, and Kavita remain available.
- Fork-specific `app.tachiyomiaz.TachiyomiAZ` app and test bundle identifiers avoid
  Aidoku signing collisions and allow both apps to coexist.
- The source-available external AidokuRunner package is no longer a dependency.
  An interpreter-free, GPL-compatible in-repository module owns the small
  model and runner protocol surface used by the UI. It contains no AIX/WASM
  loader or copied AidokuRunner implementation.

## Compatibility transition

The app still imports a module named `AidokuRunner` for source compatibility,
but that name now resolves to `Packages/TachiyomiAZRunner`, which is owned by
this fork and implements only shared manga/chapter/filter/setting models plus
the `Runner` protocol. The external AidokuRunner repository is not fetched or
linked. TachiyomiX sources use `TachiyomiXSourceRunner`; AIX/WASM loading is
rejected by the local compatibility layer.

## External validation

1. Run the configured Xcode build for an arm64 iOS Simulator on
   a macOS host. This workspace has no Xcode or iOS SDK.
2. Continue expanding the extension fixture matrix to catch uncommon Android
   graphics/resource assumptions. Android WebView calls and JavaScript/login
   challenges use native WKWebView; desktop CEF is deliberately excluded.

The requested extension-lib 1.4 and 1.6 fixtures pass. Physical arm64
device validation and a broader compatibility corpus remain desirable, but
they are not blockers for the simulator-first sideloading target.

## Validation completed in this workspace

- Extension host compiles with Temurin JDK 8 using `-source 8 -target 8`.
- Fixture JAR load/invoke/unload test passes.
- Gzipped Mihon protobuf fixture decode test passes.
- The pinned extension-lib 1.4 and 1.6 JARs are downloaded and
  checksum-verified. The 1.6 fixture uses Java 11 / class-file version 55.
- The pinned Suwayomi source API and AndroidCompat build successfully on
  JDK 21.
- A fresh Git checkout with no ignored runtime artifacts successfully
  bootstraps the checksum-pinned OpenJDK/mobile device and simulator bundles,
  rebuilds the pinned Suwayomi runtime, and passes the compact-runtime
  extension-lib 1.4/1.6 suites. Shell scripts have repository-pinned LF endings and
  executable modes for WSL, macOS, and CI checkouts.
- A minimal `java.base` + EC-crypto runtime probe, using the same boot shim as
  iOS and no desktop Logback provider, completes every extension-lib 1.4 and
  1.6 integration operation.
- The extension-lib 1.6 fixture constructs through the real compatibility layer and reports the
  expected name, language, source ID, and base URL.
- The extension-lib 1.4 fixture constructs all 61 sources from `ExtensionGenerated`, selects source
  ID `2499283573021220255` (`en`), reaches `https://api.mangadex.org`, returns
  HTTP 200, and completes popular, latest, search, details, chapter-list, and
  page-list operations through the extension-lib 1.4 fallback path.
- Extension-lib 1.4 filter descriptors are projected into native filter controls; a
  sort-state round trip changes its live API request to title/ascending.
- Extension-lib 1.4 AndroidX preferences are discovered and a select preference is
  written back through its persistent `SharedPreferences`.
- WKWebView-style cookies can be inserted into the extension-lib 1.4 fixture's persistent
  OkHttp cookie jar, inspected without exposing values, and cleared.
- Extension-lib 1.4 page context survives the JNI boundary and reconstructs the
  extension-specific image request, headers, and cookie jar for Aidoku's
  native image pipeline.
- Its coroutine popular-manga method reaches
  `https://api.asurascans.com/api/series`, returns HTTP 200, and decodes 20
  typed manga summaries with `hasNextPage = true`.
- JNI C++ bridge compiles with `-std=c++17 -Wall -Wextra -Werror`.
- Git whitespace checks pass.
- The nightly macOS job builds the matching iOS 15 OpenJDK device/simulator
  runtime and produces the device archive.

Xcode, Swift, and an iOS SDK are not installed in the current Linux/WSL
workspace, so an honest Xcode compile or device-runtime claim cannot be made
here.
