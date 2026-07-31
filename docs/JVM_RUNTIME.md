# JVM extension runtime

## Status

This branch is introducing a second source runtime for direct Tachiyomi/Mihon
extension JARs. It does not use `dex2jar`: extension repositories are expected
to provide JVM class JAR artifacts.

The first implementation slice consists of:

- `Packages/TachiJVMRunner`: Swift/JNI bridge and persistent VM owner.
- `Runtime/ExtensionHost`: Java-side classloader and request dispatcher.
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
- `loadExtension`
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
2. Set `TACHIAZ_BUILD_JAVA_HOME` to a JDK 8+ installation.
3. Run `Scripts/build-extension-host.sh --test`.
4. Run `Scripts/test-keiyoushi-asurascans.sh`.

The host itself is compiled as Java 8 bytecode for portability. Extension
validation is based on the embedded VM's actual class-file ceiling. The pinned
Asura Scans `1.6.66` fixture uses Java 11 bytecode (major version 55), which is
why the old third-party OpenJDK 8 build was replaced with the current official
OpenJDK/mobile snapshot.

Keiyoushi JARs contain a textual `AndroidManifest.xml`. The host reads
`tachiyomi.extension.class`, package name, display name, version, extension-lib
version, SDK levels, and bytecode requirements directly from that manifest.
It does not perform APK or DEX conversion.

`KeiyoushiJarRepository` maps an index filename such as
`tachiyomi-en.asurascans-v1.6.66.apk` to the supplied repository artifact
`repo/jar/tachiyomi-en.asurascans-v1.6.66.jar`. Path separators are rejected
before constructing the download URL.

## Compatibility scope

The next layer must provide the Android and Mihon APIs commonly used by
Keiyoushi-compatible extensions. It should begin with HTTP, preferences,
HTML parsing, source models, and basic Android resource access. Unsupported
Android UI, WebView, and service APIs will fail with explicit compatibility
errors rather than silent stubs.

## Security model

Java extensions are native-trust plugins from the app's point of view. They can
consume CPU and memory, access any Java API exposed by the host, and crash the
process through runtime bugs. Installation must therefore require a trusted
repository, artifact checksums, and a visible permission/capability summary.
