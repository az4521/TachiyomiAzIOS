# OpenJDK/mobile runtime

TachiAZ uses the official
[`openjdk-mobile/ios-tools`](https://github.com/openjdk-mobile/ios-tools)
device and simulator snapshot. The binaries are intentionally not checked into
this repository.

For the iOS 15-compatible runtime, use macOS with OpenJDK 24 as the active
boot JDK, then run:

```sh
Scripts/build-openjdk-ios15.sh
```

The script builds a checksum- and revision-pinned OpenJDK Mobile 26 Zero VM,
matching macOS image tools,
matching `java.base` module images, and an XCFramework with arm64 device and
arm64 simulator slices. Both native targets are compiled with an explicit iOS
15 deployment target. CI caches the complete matching runtime using a key
derived from the build script and compatibility patch, and skips compilation
on unrelated commits.
The build applies the tracked iOS runtime compatibility patch in
`Scripts/patches/` and records the Java module target as Darwin/aarch64 because
the pinned revision's `jlink` predates a distinct iOS platform enum.
The Java images also include `jdk.crypto.ec` for modern TLS, `jdk.unsupported`
for libraries that use `sun.misc` compatibility APIs, required security and
time-zone data, and the corresponding OpenJDK legal notices.

`Scripts/bootstrap-openjdk-ios.sh` remains available only for inspecting the
upstream snapshot. Do not mix its Java 27 module images with this Java 26 VM.

The snapshot class-library image contains only `java.base`. The build also
embeds `Runtime/MobileShims/dist/tachiaz-mobile-shims.jar` on the boot
classpath for the small JUL surface used by OkHttp/Okio, and installs a JDK
CA trust store into `java_bundle/lib/security/cacerts`. Run
`Scripts/build-mobile-shims.sh` before building outside CI.

The current TachiyomiX extension-lib 1.6 fixture uses Java 11 class files. The
former OpenJDK 8 experiment cannot load it, so it is deliberately unsupported.

This runtime is for sideloaded builds. The Java interpreter is initialized once
per app process; Java extensions run in-process and therefore share the app's
permissions and crash boundary.
