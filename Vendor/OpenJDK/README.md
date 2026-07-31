# OpenJDK/mobile runtime

TachiAZ uses the official
[`openjdk-mobile/ios-tools`](https://github.com/openjdk-mobile/ios-tools)
device and simulator snapshot. The binaries are intentionally not checked into
this repository.

Run:

```sh
Scripts/bootstrap-openjdk-ios.sh
```

The bootstrap script downloads checksum-pinned copies of
`OpenJDK.xcframework.zip`, `java_bundle-device.zip`, and
`java_bundle-simulator.zip`. The XCFramework contains `arm64` device plus
`arm64` and `x86_64` simulator slices. Xcode embeds the matching class-library
bundle as `java_bundle` for the selected destination.

The current Keiyoushi Asura Scans JAR uses Java 11 class files. The former
OpenJDK 8 experiment cannot load it, so it is deliberately unsupported.

This runtime is for sideloaded builds. The Java interpreter is initialized once
per app process; Java extensions run in-process and therefore share the app's
permissions and crash boundary.
