# TachiyomiAZ iOS Fork Plan

Status: implemented; macOS Xcode validation pending (see
`docs/IMPLEMENTATION_STATUS.md`)
Last updated: 2026-07-31

## 1. Executive summary

Build a sideload-only iOS/iPadOS manga reader by forking Aidoku and replacing
Aidoku's WASM source runtime with a JVM-based Mihon-compatible extension
runtime.

The application will:

- retain Aidoku's native reader, downloads, library, persistence, tracking, and
  most feature screens;
- embed the official OpenJDK/mobile Zero-interpreter runtime on iOS;
- load JVM JAR versions of Mihon/TachiyomiX extensions directly;
- reuse a targeted subset of Suwayomi's extension API and AndroidCompat layer;
- import TachiyomiAZ and Mihon backups while preserving source IDs and
  manga/chapter keys;
- replace Aidoku's tab bar with a Material Design 1-inspired hamburger drawer;
- target sideloading rather than App Store or TestFlight distribution.

This is not a full TachiyomiAZ port. It is an Aidoku-based native iOS client
whose source subsystem is compatible with the Mihon extension ecosystem.

## 2. Goals

### Core goals

1. Run direct JVM extension JARs supplied by the extension distribution system.
2. Preserve Mihon source IDs, manga URLs, and chapter URLs.
3. Import normal `.tachibk` backups from Mihon and TachiyomiAZ.
4. Keep Aidoku's native iOS reader and download experience.
5. Provide a Material Design 1-inspired navigation drawer and visual theme.
6. Work in the arm64/x86_64 iOS Simulator and on physical arm64 iPhones and
   iPads through sideloading.

### Compatibility goals

- Library entries
- Categories and category order
- Read status and last-read page
- Bookmarks
- Reading history
- Track records when the tracker is supported
- Source and extension preferences where practical
- Extension repository installation and updates

### Non-goals for the first release

- App Store or TestFlight distribution
- Aidoku WASM/aidoku-rs source compatibility
- Lossless export back to every Tachiyomi fork
- Importing downloaded chapter files from an Android device
- Running extensions that require Android-native `.so` libraries
- Perfect emulation of the complete Android SDK
- Rewriting the manga reader in Material Design

## 3. Scope simplifications

- Retain AidokuRunner's model and `Runner` protocol surface for the existing
  app, but use the JVM host for the production iOS online-source execution
  path. Interpreter-backed sources are not installed or reloaded on iOS.
- Remove Aidoku-specific delegated-source behavior from the iOS UI and backup
  restore path.
- Do not port bespoke E-Hentai/ExHentai integration or migration code.
- Treat all supported sources through the generic JVM extension interface.
- Retain Aidoku's reader implementation and restyle only its surrounding
  controls where necessary.
- Keep Aidoku's database as the application database. Do not embed the complete
  Suwayomi Server, Javalin, or Suwayomi database.

## 4. High-level architecture

```text
Extension repository
        |
        | metadata + JVM extension JAR
        v
Swift Extension Manager
        |
        v
OpenJDK/mobile Zero JVM (one persistent instance)
        |
        v
Java ExtensionHost facade
        |
        +-- isolated URLClassLoader per extension/version
        +-- Mihon extension API
        +-- Kotlin/runtime dependencies
        +-- reduced Suwayomi AndroidCompat
        |
        v
Swift/JNI bridge
        |
        +-- URLSession networking and cookies
        +-- preferences and secure storage
        +-- WKWebView challenges when required
        +-- image and JavaScript native services
        |
        v
Aidoku models, Core Data, downloads, and reader
```

## 5. JVM runtime

### Selected starting point

Use the official OpenJDK/mobile iOS Zero build and XCFramework:

- OpenJDK/mobile:
  https://github.com/openjdk/mobile
- iOS packaging tools and snapshots:
  https://github.com/openjdk-mobile/ios-tools

The earlier OpenJDK 8 build demonstrated by Code App proved that the approach
works, but it cannot load the extension-lib 1.6 fixture because that fixture
uses Java 11 class files.

Zero interprets bytecode and does not depend on JIT availability. This allows
new extension JARs to be downloaded and loaded at runtime.

### Integration approach

Do not copy Code App's command-line `JLI_Launch` lifecycle. Start one persistent
VM with the JNI Invocation API:

1. Link the bundled static OpenJDK XCFramework.
2. Configure `JAVA_HOME` and the runtime classpath.
3. Call `JNI_CreateJavaVM` once during source-runtime initialization.
4. Keep the VM alive until process termination.
5. Attach and detach native worker threads correctly.
6. Route all extension operations through a small Java `ExtensionHost` API.

The VM should never call `System.exit`. VM destruction/recreation is not part of
the normal lifecycle.

### Bytecode compatibility gate

The host must inspect each extension's maximum class-file version and compare
it to the embedded VM's reported ceiling. The extension-lib 1.6 test baseline
uses class-file version 55 (Java 11). Host-side compatibility code
remains Java 8 bytecode where practical, but extensions are not artificially
restricted to Java 8.

Reject incompatible JARs before attempting to load them and show a useful error
containing the detected class-file version.

## 6. Java extension host

Create a narrow, versioned Java facade rather than exposing arbitrary Java
objects to Swift.

Candidate operations:

```text
boot(configuration)
loadExtension(jarPath, metadata)
unloadExtension(extensionId)
listSources(extensionId)
getPopular(sourceId, page)
getLatest(sourceId, page)
search(sourceId, query, filters, page)
getMangaDetails(sourceId, mangaKey)
getChapterList(sourceId, mangaKey)
getPageList(sourceId, chapterKey)
getFilters(sourceId)
getPreferences(sourceId)
setPreference(sourceId, key, value)
```

Use JSON or protobuf DTOs across JNI initially. Avoid exposing Kotlin
coroutines, RxJava objects, or large Java object graphs directly to Swift.

Each extension version receives its own isolated class loader. On update:

1. stop new work for the old loader;
2. allow outstanding calls to finish or cancel them;
3. remove application references to the old loader;
4. create a new loader for the new JAR;
5. retain the old JAR until the update succeeds;
6. roll back if source enumeration or a smoke test fails.

Class-loader unloading is best-effort; memory use must be measured during
repeated updates.

## 7. Android compatibility layer

Start from the linked Suwayomi AndroidCompat implementation:

https://github.com/Suwayomi/Suwayomi-Server/tree/eb2dc0b19a9571b27c02bebc5c883e404b7bd7fb/AndroidCompat

Port only what source extensions require. Do not bring in the whole server.

### Initial required surface

- `android.content.Context`
- `SharedPreferences`
- `android.net.Uri`
- `Bundle`
- `Handler` and `Looper`
- Android preference classes
- package and extension metadata
- resource and asset access
- cookie management
- basic Bitmap/Canvas/Color/Rect operations
- QuickJS-compatible execution
- extension `Source`, `CatalogueSource`, `HttpSource`, `ParsedHttpSource`, and
  `SourceFactory` APIs

### Native services

Prefer iOS-native implementations behind a small Java API:

- HTTP: `URLSession`
- Cookies: shared `HTTPCookieStorage` or a dedicated cookie store
- Interactive challenges: `WKWebView`
- Images: ImageIO/CoreGraphics
- JavaScript: JavaScriptCore or a bundled QuickJS implementation
- Preferences: Aidoku/Core Data or files in the app container

Pure-Java OkHttp can be used for the first proof of concept. Native networking
becomes important for cookie sharing, challenge handling, background behavior,
and consistent iOS TLS behavior.

## 8. Extension management

### Installation

1. Fetch extension repository metadata.
2. Download the supplied JVM JAR.
3. Verify its checksum and repository/signature policy.
4. Validate its bytecode and declared extension API version.
5. Store it under an application-managed extensions directory.
6. Load it in a new isolated class loader.
7. Enumerate `Source` or `SourceFactory` instances.
8. Persist package, version, source IDs, language, and preferences metadata.

### Updates

- Check repository metadata on demand and periodically.
- Download to a staging location.
- Verify before activation.
- Smoke-test source enumeration.
- Switch atomically and retain one rollback version.
- Show extensions that failed compatibility checks separately from network
  errors.

### Trust model

JAR extensions execute trusted code inside the application process and do not
have WASM-style isolation. Initially:

- allow only explicitly configured repositories;
- verify hashes and signatures where provided;
- display repository and signer information;
- require explicit trust for unknown repositories;
- never load a JAR directly from an arbitrary URL without confirmation.

## 9. Aidoku integration

Introduce a Swift protocol that isolates the application from the concrete
runtime:

```text
SourceRuntime
  - installedSources
  - popular
  - latest
  - search
  - mangaDetails
  - chapters
  - pages
  - filters
  - preferences
```

Implement `JVMSourceRuntime` using the JNI bridge. Adapt existing Aidoku source
call sites to the protocol, then remove the AidokuRunner implementation and
dependency.

Use Mihon's numeric source ID represented losslessly as an `Int64` or decimal
string. Preserve the extension-provided manga and chapter keys without
normalizing them.

## 10. Backup compatibility

### Format support

- Detect gzip and decompress `.tachibk` data.
- Decode Kotlinx Serialization protobuf using SwiftProtobuf-generated models.
- Accept both current Mihon backups and TachiyomiAZ's compatible superset.
- Ignore unknown optional TachiyomiAZ fields unless later support is valuable.

### Import behavior

The importer must merge transactionally; it must not call Aidoku's normal
restore path that clears existing records.

Import:

- manga metadata;
- favorite/library membership;
- categories and ordering;
- chapters;
- read state;
- last page read;
- bookmarks;
- history and reading duration;
- supported tracker records;
- source preferences where their schema is available;
- update strategy and viewer flags where there is an iOS equivalent.

Because the JVM runtime uses the same source IDs and keys, titles should
reconnect directly to their extension whenever that extension is installed.

### Missing extensions

Keep imported entries even when their extension is unavailable:

- mark them as requiring an extension;
- show the expected package/source ID;
- allow installation from a configured repository;
- refresh metadata and chapters after the source becomes available.

### Safety

- Show a dry-run summary before committing.
- Create an Aidoku-native backup before import.
- Use one Core Data transaction/background context.
- Roll back the complete import on a fatal error.
- Produce an import report with imported, merged, skipped, and unresolved
  counts.

## 11. Material Design 1 navigation and appearance

Replace Aidoku's `UITabBarController` root with a drawer container while
retaining the existing feature navigation controllers.

### Drawer destinations

- Library
- Updates/History
- Browse/Sources
- Extensions
- Search
- Downloads
- Settings

### Behavior

- Hamburger button on root screens
- Normal back button on pushed screens
- Edge-pan opening gesture
- Dimming scrim
- Active destination highlight
- Extension-update badge
- Approximately 280-320 point drawer on phones
- Persistent sidebar/split layout on regular-width iPad
- Keyboard shortcuts retained or reassigned

### MD1 design system

Create central design tokens and reusable components for:

- primary, primary-dark, and accent colors;
- toolbars and elevation shadows;
- list rows and dividers;
- cards;
- buttons and optional floating action buttons;
- typography;
- navigation icons and selection states.

Apply the theme in this order:

1. application shell and drawer;
2. Library;
3. Browse, Sources, and Extensions;
4. manga details and chapter list;
5. history, downloads, and settings;
6. reader chrome.

Do not rewrite the reader's layout engine solely for visual parity.

## 12. Delivery phases

### Phase 0: repository and build baseline

- Confirm the Aidoku fork builds on the supported Xcode version.
- Document all third-party licenses.
- Remove unused source/delegation features only after tests establish a
  baseline.

Estimate: 1 week.

### Phase 1: JVM feasibility prototype

- [x] Embed the OpenJDK Zero runtime.
- [x] Start one VM through `JNI_CreateJavaVM`.
- [x] Call a bundled Java test facade from Swift.
- [x] Load one direct extension JAR.
- [x] Fetch popular entries from the pinned extension-lib 1.6 fixture.
- [x] Fetch popular/latest/search/details/chapters/pages from the pinned
  extension-lib 1.4 fixture.
- [x] Package separate arm64-device and arm64/x86_64-simulator Java bundles.
- Measure startup time, memory, and battery use on physical devices.

Estimate: 1-3 weeks.

This is the primary go/no-go gate.

### Phase 2: extension runtime

- Build the Java facade and DTO protocol.
- Compile the extension API and AndroidCompat subset for JVM 8.
- Add class-loader lifecycle management.
- Implement preferences, assets, repository management, and updates.
- Add native networking/cookies and challenge handling.

Estimate: 6-12 weeks.

### Phase 3: Aidoku source integration

- Introduce `SourceRuntime`.
- Replace AidokuRunner call sites.
- Adapt source, manga, chapter, page, filter, and preference models.
- Remove WASM source management after the JVM path reaches feature parity.

Estimate: 3-6 weeks.

### Phase 4: Mihon/TachiyomiAZ backup import

- Implement protobuf/gzip decoding.
- Add transactional import and duplicate handling.
- Restore source IDs, keys, categories, progress, history, and trackers.
- Add missing-extension and import-report screens.
- Test large real-world backups.

Estimate: 3-6 weeks.

### Phase 5: hamburger shell and MD1 theme

- Replace the tab bar with the drawer container.
- Repair tab-bar-specific assumptions.
- Add iPad split/sidebar behavior.
- Apply design tokens to top-level screens.
- Progressively restyle secondary screens.

Estimate: 4-10 weeks depending on visual coverage.

### Phase 6: hardening

- Suspend/resume testing
- Low-memory testing
- Repeated extension update testing
- Large library and backup testing
- Corrupt/malicious JAR handling
- Network and WebView challenge testing
- Crash recovery and rollback

Estimate: 3-6 weeks.

## 13. Milestones and acceptance gates

### Milestone A: runtime proven

- Persistent JVM boots reliably on a physical device.
- A direct extension JAR loads without JIT.
- At least one source completes the full browse-to-page-list flow.

### Milestone B: representative compatibility

At least five representative extensions work:

- simple parsed HTTP source;
- multisource extension;
- preferences-heavy source;
- JavaScript-dependent source;
- cookie or WebView-dependent source.

### Milestone C: backup round trip into the app

- A real Mihon backup imports successfully.
- A real TachiyomiAZ backup imports successfully.
- Installed-source titles refresh without fuzzy remapping.
- Missing-source titles remain recoverable.

### Milestone D: usable application

- Drawer navigation replaces the tab bar.
- Library, browsing, reading, and downloads are stable.
- Extension installation/update and backup import have user-facing error
  reporting and rollback.

## 14. Risks

### OpenJDK maintenance

The official iOS port is active but still young. Pin release checksums, retain
the ability to build snapshots, and expect device-specific runtime fixes.

### JVM bytecode drift

Extensions may raise their target beyond the bundled VM. Automated bytecode
validation and a useful required-Java-version error remain mandatory.

### Memory and startup cost

A JVM, Kotlin runtime, AndroidCompat, and multiple class loaders are heavier
than AidokuRunner. Measure early on older supported devices and avoid embedding
the full Suwayomi server.

### Android API gaps

Some extensions will expose missing classes or methods only at runtime. Maintain
a compatibility test suite and show actionable incompatibility errors.

### Native dependencies

Android `.so` libraries cannot run on iOS. Extensions requiring them are
unsupported until an iOS-native replacement exists.

### Untrusted code

JARs execute with the application's permissions. Repository allowlists,
signature/hash verification, and clear trust UI are required.

### Class-loader retention

Updated loaders may remain reachable and consume memory. Track loader ownership,
clear caches on update, and measure repeated update cycles.

## 15. Testing strategy

- Java unit tests for `ExtensionHost` and AndroidCompat
- Swift unit tests for JNI DTO conversion
- Contract tests shared between Swift and Java
- Golden backup decoding tests for Mihon and TachiyomiAZ
- Import rollback and duplicate tests
- Extension compatibility fixtures
- Physical-device performance tests
- UI tests for drawer navigation and restore flows
- Long-running library update and download tests

No real source credentials, cookies, or private backup data should be committed
to the repository.

## 16. Licensing notes

- Aidoku application code remains subject to GPLv3 and its contributor/distribution
  terms.
- Replacing AidokuRunner avoids depending on AidokuRunner's separate
  source-available redistribution restriction.
- Suwayomi changes are generally MPL-2.0, while portions of AndroidCompat and
  inherited Tachiyomi code are Apache-2.0; preserve notices and review exact
  file provenance.
- OpenJDK has its own GPLv2-with-Classpath-Exception obligations.
- Extension JARs retain their respective licenses.

Sideload-only scope removes App Store review as a product requirement but does
not remove software-license obligations.

## 17. Current recommendation

Proceed with Phase 1 before beginning backup UI or broad Aidoku refactoring.
The decisive technical question is whether the selected OpenJDK Zero build can
load the actual direct extension JARs and run a representative set of sources
within acceptable memory and performance limits.

If Phase 1 passes, this architecture is preferable to AidokuRunner for this
project because it preserves Mihon source identity and makes backup restoration
substantially more reliable.
