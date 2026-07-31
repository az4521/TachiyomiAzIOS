# OpenJDK/mobile runtime

TachiAZ uses the official
[`openjdk-mobile/ios-tools`](https://github.com/openjdk-mobile/ios-tools)
device snapshot. The binaries are intentionally not checked into this
repository.

Run:

```sh
Scripts/bootstrap-openjdk-ios.sh
```

The bootstrap script downloads checksum-pinned copies of
`OpenJDK.xcframework.zip` and `java_bundle-device.zip`. It installs the static
Zero VM XCFramework and device class-library bundle in this directory.

The current Keiyoushi Asura Scans JAR uses Java 11 class files. The former
OpenJDK 8 experiment cannot load it, so it is deliberately unsupported.

This runtime is for sideloaded builds. The Java interpreter is initialized once
per app process; Java extensions run in-process and therefore share the app's
permissions and crash boundary.
