# JVM extension runtime

## Status

This branch is introducing a second source runtime for direct Tachiyomi/Mihon
extension JARs. It does not use `dex2jar`: extension repositories are expected
to provide JVM class JAR artifacts.

The first implementation slice consists of:

- `Packages/TachiJVMRunner`: Swift/JNI bridge and persistent VM owner.
- `Runtime/ExtensionHost`: Java-side classloader and request dispatcher.
- `Runtime/ExtensionHost/compat`: generated, pinned Suwayomi source API and
  AndroidCompat runtime.
- `Vendor/OpenJDK`: revision-pinned OpenJDK/mobile 26 Zero runtime for iOS
  devices and Apple Silicon iOS simulators, built with an iOS 15 target.

On iOS, the production online-source execution path is now the JVM host. The
external source-available AidokuRunner package is not linked. A local module
with the same import name provides independently maintained UI models and its
runner protocol without an interpreter implementation. The AIX/WASM installer,
stored-interpreter reload path, and delegated source lists are disabled.

## Runtime contract

Swift sends UTF-8 JSON requests to
`app.tachiaz.runtime.ExtensionHost.dispatch(String)`. The host currently
supports:

- `ping`
- `inspectExtension`
- `initializeCompatibility`
- `loadExtension`
- `listSources`
- `getPopularManga`
- `getLatestUpdates`
- `searchManga`
- `getSearchFilters`
- `getSettings`
- `setSetting`
- `getMangaUpdate`
- `getPageList`
- `getImageRequest`
- `invoke`
- `unloadExtension`
- `decodeBackup`

Each extension is isolated by its own `URLClassLoader`, but all classloaders
live in one JVM and one iOS process. This is namespace isolation, not a security
boundary.

The JNI bridge creates one VM and attaches caller threads as needed. It never
destroys or restarts the VM because HotSpot/OpenJDK does not support reliable
in-process VM recreation.

`user.home` is explicitly rooted at `Application Support/JVMHome` and
`java.io.tmpdir` at the app's temporary directory. AndroidCompat preferences,
configuration, and persistent cookies therefore stay inside the iOS app
sandbox on both simulator and device.

## Build prerequisites

1. Install OpenJDK 24 on macOS and run `Scripts/build-openjdk-ios15.sh`. JDK 24
   is the boot JDK used by the known-good source revision. The script also
   builds matching `jmod` and `jlink` image tools from that exact revision.
2. Set `TACHIYOMIAZ_BUILD_JAVA_HOME` to that JDK 24 installation (the
   compatibility builds accept JDK 21 or newer).
3. Run `Scripts/bootstrap-suwayomi-compat.sh`.
4. Run `Scripts/build-mobile-shims.sh`.
5. Run `Scripts/build-extension-host.sh --test`.
6. Run `Scripts/test-mobile-java-base.sh`.

The real-world tests intentionally contain no extension-repository address.
Supply the fixture JARs directly, or set `TACHIYOMIAZ_EXTLIB_1_4_FIXTURE_URL`
and `TACHIYOMIAZ_EXTLIB_1_6_FIXTURE_URL` before running the final test script.

The host itself is compiled as Java 8 bytecode for portability. Extension
validation is based on the embedded VM's actual class-file ceiling. The pinned
extension-lib 1.6 fixture uses Java 11 bytecode (major version 55), which is
why the old third-party OpenJDK 8 build was replaced with OpenJDK/mobile 26.

TachiyomiX JARs contain a textual `AndroidManifest.xml`. The host reads
`tachiyomi.extension.class`, package name, display name, version, extension-lib
version, SDK levels, and bytecode requirements directly from that manifest.
It does not perform APK or DEX conversion.

The compatibility bootstrap checks out Suwayomi-Server commit
`eb2dc0b19a9571b27c02bebc5c883e404b7bd7fb`, builds AndroidCompat and the
Mihon source implementation, and copies a tested 36-JAR runtime subset. The
generated compatibility directory is about 57 MB before iOS app packaging.
The Xcode build embeds it as `tachiaz-compat`. The complete AndroidCompat and
Mihon API compatibility subset is first on the application classpath. Only the
iOS-safe `SystemClock` replacement is placed in the boot shim, where it wins
before application class loading. Desktop Logback providers are deliberately
excluded.

The app consumes current extension-lib `index.pb` protobuf stores and their
equivalent object-shaped `index.json` representation only from repositories
explicitly configured by the user. Legacy `repo.json` and array-shaped
`index.min.json` formats are intentionally unsupported. No repository URL is
built into the app. Users may enter an index URL or its containing directory;
the catalog is validated before the URL is persisted. Catalog entries provide direct
`jarUrl` artifacts. Before installation,
the downloaded JAR is inspected and its package/version must match the
catalog metadata; its locally computed SHA-256 is then persisted with the
manifest. Installed `SourceFactory` entries become individual Aidoku sources
using stable `mihon.<sourceId>` keys.

Extension manifests are accepted only when `tachiyomix.extensionLib` is in the
supported `1.4` through `1.6` range. The host always invokes the suspend
operation. For extension-lib 1.4 and other legacy sources, the supplied
Mihon-compatible `CatalogueSource` default delegates that call to the
extension's Rx `fetch*` implementation. Extension-lib 1.6 sources that
override the suspend method run directly. Tests cover both paths using pinned
extension-lib 1.4 and extension-lib 1.6 fixtures. The 1.4 fixture also verifies
`SourceFactory` support: its generated entry point
expands into 61 language-specific sources, which Swift can list and address
by Mihon source ID.

## Compatibility scope

The pinned Suwayomi layer now supplies HTTP, preferences, HTML parsing, source
models, filters, cookies, and its Android compatibility classes. Typed popular,
latest, search/filter, combined manga-details/chapter-update, page-list, and
preference operations invoke TachiyomiX's API without exposing Kotlin objects
across JNI. On 1.4 extensions, Mihon's default implementations bridge source
calls to the legacy Rx methods. AndroidX preferences are projected into native
Aidoku settings and written back to the extension's `SharedPreferences`.
Reader pages retain their original Mihon page URL as native page context; the
host uses it to reconstruct `HttpSource.imageRequest`, then forwards headers
and persistent cookies to Aidoku's native image pipeline.
Extension-owned manga and chapter `memo` values remain opaque JSON: the host
round-trips them without interpretation and the app persists them in Core Data.

On iOS, the AndroidCompat `WebView` provider is replaced after compatibility
initialization with a bridge to WKWebView. It supports loading URLs/HTML,
posting data, JavaScript evaluation and annotated JavaScript interfaces,
asynchronous navigation, main-navigation and scripted-fetch interception,
modern error/render callbacks, console output, history, user agents, progress
callbacks, and the commonly queried page properties. The reverse JNI callback
path attaches WebKit threads to the existing VM and dispatches lifecycle work
onto AndroidCompat's main Looper without blocking it. The
Android `CookieManager` singleton uses `WKHTTPCookieStore`; browser cookies are
mirrored to `HTTPCookieStorage`, base-origin HTML loads receive matching stored
cookies before navigation, and explicit Cloudflare handling additionally
copies the solved cookies and matching user agent into the extension's OkHttp
client before its failed request is retried. Desktop KCEF/JCEF is not packaged.
Unsupported Android behavior must fail explicitly rather than silently
returning incorrect data.

## Security model

Java extensions are native-trust plugins from the app's point of view. They can
consume CPU and memory, access any Java API exposed by the host, and crash the
process through runtime bugs. Installation must therefore require a trusted
repository plus package/version identity validation. TachiyomiAZ records the
downloaded artifact's SHA-256 in its installed manifest so later storage
corruption or substitution can be detected.
