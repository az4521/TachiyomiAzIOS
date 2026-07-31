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
- `Vendor/OpenJDK`: checksum-pinned official OpenJDK/mobile Zero runtime.

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
- `getPopularManga`
- `invoke`
- `unloadExtension`
- `decodeBackup`

Each extension is isolated by its own `URLClassLoader`, but all classloaders
live in one JVM and one iOS process. This is namespace isolation, not a security
boundary.

The JNI bridge creates one VM and attaches caller threads as needed. It never
destroys or restarts the VM because HotSpot/OpenJDK does not support reliable
in-process VM recreation.

## Build prerequisites

1. Run `Scripts/bootstrap-openjdk-ios.sh` on macOS.
2. Set `TACHIAZ_BUILD_JAVA_HOME` to a JDK 21+ installation.
3. Run `Scripts/bootstrap-suwayomi-compat.sh`.
4. Run `Scripts/build-extension-host.sh --test`.
5. Run `Scripts/test-keiyoushi-asurascans.sh`.

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
Mihon source implementation, and copies a tested 38-JAR runtime subset. The
generated compatibility directory is about 57 MB before iOS app packaging.
The Xcode build embeds it as `tachiaz-compat`, ahead of the extension-host JAR
on the JVM classpath so the full AndroidCompat classes take precedence over
the host-only fixture stubs.

`KeiyoushiJarRepository` maps an index filename such as
`tachiyomi-en.asurascans-v1.6.66.apk` to the supplied repository artifact
`repo/jar/tachiyomi-en.asurascans-v1.6.66.jar`. Path separators are rejected
before constructing the download URL.

Extension manifests are accepted only when `tachiyomix.extensionLib` is in the
supported `1.4` through `1.6` range. The host always invokes the suspend
operation. For extension-lib 1.4 and other legacy sources, the supplied
Mihon-compatible `CatalogueSource` default delegates that call to the
extension's Rx `fetch*` implementation. Extension-lib 1.6 sources that
override the suspend method run directly. Tests cover both paths using a
fixture compiled against official TachiyomiX 1.4.4 and the real Keiyoushi
Asura Scans 1.6.66 JAR.

## Compatibility scope

The pinned Suwayomi layer now supplies HTTP, preferences, HTML parsing, source
models, filters, cookies, and its Android compatibility classes. The first
typed operation invokes Keiyoushi's coroutine `getPopularManga` method without
exposing Kotlin objects across JNI and returns a Swift-decodable manga page.
Latest/search/details/chapters/pages/filter/preference operations still need
equivalent DTO bridges. Unsupported Android behavior must fail explicitly
rather than silently returning incorrect data.

## Security model

Java extensions are native-trust plugins from the app's point of view. They can
consume CPU and memory, access any Java API exposed by the host, and crash the
process through runtime bugs. Installation must therefore require a trusted
repository, artifact checksums, and a visible permission/capability summary.
