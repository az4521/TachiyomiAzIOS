# OpenJDK/mobile runtime

TachiAZ uses the official
[`openjdk-mobile/ios-tools`](https://github.com/openjdk-mobile/ios-tools)
device and simulator snapshot. The binaries are intentionally not checked into
this repository.

Run:

```sh
Scripts/bootstrap-openjdk-ios.sh
```

The upstream snapshot's device objects currently inherit the build machine's
iOS 17.5 deployment target. To support the app's iOS 15 minimum, macOS builds
must then run:

```sh
Scripts/rebuild-openjdk-device-ios.sh
```

This checksum-pinned rebuild uses the same OpenJDK Mobile revision as the
bundled Java 27 module image, but compiles the device runtime with an explicit
iOS 15 deployment target. CI caches the resulting device XCFramework slice.

The bootstrap script downloads checksum-pinned copies of
`OpenJDK.xcframework.zip`, `java_bundle-device.zip`, and
`java_bundle-simulator.zip`. The XCFramework contains `arm64` device plus
`arm64` and `x86_64` simulator slices. Xcode embeds the matching class-library
bundle as `java_bundle` for the selected destination.

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
