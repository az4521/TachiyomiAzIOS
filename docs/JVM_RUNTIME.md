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
- `Vendor/OpenJDK`: checksum-pinned official OpenJDK/mobile Zero runtime for
  iOS devices and Apple Silicon/Intel iOS simulators.

The existing Aidoku source runtime remains available while feature parity is
built. Removing `AidokuRunner` before the Java compatibility surface is usable
would make the fork unable to browse any sources.

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

1. Run `Scripts/bootstrap-openjdk-ios.sh` on macOS. It installs both device
   and simulator Java bundles.
2. Set `TACHIAZ_BUILD_JAVA_HOME` to a JDK 21+ installation.
3. Run `Scripts/bootstrap-suwayomi-compat.sh`.
4. Run `Scripts/build-mobile-shims.sh`.
5. Run `Scripts/build-extension-host.sh --test`.
6. Run `Scripts/test-mobile-java-base.sh`.

The host itself is compiled as Java 8 bytecode for portability. Extension
validation is based on the embedded VM's actual class-file ceiling. The pinned
Asura Scans `1.6.66` fixture uses Java 11 bytecode (major version 55), which is
why the old third-party OpenJDK 8 build was replaced with the current official
OpenJDK/mobile snapshot.

Keiyoushi JARs contain a textual `AndroidManifest.xml`. The host reads
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

`KeiyoushiJarRepository` maps an index filename such as
`tachiyomi-en.asurascans-v1.6.66.apk` to the supplied repository artifact
`repo/jar/tachiyomi-en.asurascans-v1.6.66.jar`. Path separators are rejected
before constructing the download URL.

The app also consumes Keiyoushi's current extension-lib 1.6 `index.json`
format. Catalog entries provide direct `jarUrl` artifacts. Before installation,
the downloaded JAR is inspected and its package/version must match the
catalog metadata; its locally computed SHA-256 is then persisted with the
manifest. Installed `SourceFactory` entries become individual Aidoku sources
using stable `mihon.<sourceId>` keys.

Extension manifests are accepted only when `tachiyomix.extensionLib` is in the
supported `1.4` through `1.6` range. The host always invokes the suspend
operation. For extension-lib 1.4 and other legacy sources, the supplied
Mihon-compatible `CatalogueSource` default delegates that call to the
extension's Rx `fetch*` implementation. Extension-lib 1.6 sources that
override the suspend method run directly. Tests cover both paths using a
fixture compiled against official TachiyomiX 1.4.4, the real Keiyoushi
MangaDex 1.4.211 JAR, and the real Keiyoushi Asura Scans 1.6.66 JAR.
MangaDex also verifies `SourceFactory` support: its generated entry point
expands into 61 language-specific sources, which Swift can list and address
by Mihon source ID.

## Compatibility scope

The pinned Suwayomi layer now supplies HTTP, preferences, HTML parsing, source
models, filters, cookies, and its Android compatibility classes. Typed popular,
latest, search/filter, combined manga-details/chapter-update, page-list, and
preference operations invoke Keiyoushi's API without exposing Kotlin objects
across JNI. On 1.4 extensions, Mihon's default implementations bridge source
calls to the legacy Rx methods. AndroidX preferences are projected into native
Aidoku settings and written back to the extension's `SharedPreferences`.
Reader pages retain their original Mihon page URL as native page context; the
host uses it to reconstruct `HttpSource.imageRequest`, then forwards headers
and persistent cookies to Aidoku's native image pipeline.
Unsupported Android behavior must fail explicitly rather than silently
returning incorrect data.

## Security model

Java extensions are native-trust plugins from the app's point of view. They can
consume CPU and memory, access any Java API exposed by the host, and crash the
process through runtime bugs. Installation must therefore require a trusted
repository plus package/version identity validation. TachiAZ records the
downloaded artifact's SHA-256 in its installed manifest so later storage
corruption or substitution can be detected.
