# OpenJDK runtime

TachiAZ uses the iOS OpenJDK 8 Zero build published by
[`thebaselab/android-openjdk-build-multiarch`](https://github.com/thebaselab/android-openjdk-build-multiarch).
The binaries are intentionally not checked into this repository.

Run:

```sh
Scripts/bootstrap-openjdk-ios.sh
```

The bootstrap script downloads the pinned `v0.2` archive, verifies its SHA-256
checksum, and installs `java-8-openjdk` plus the dynamic frameworks in this
directory.

This runtime is for sideloaded builds. The Java interpreter is initialized once
per app process; Java extensions run in-process and therefore share the app's
permissions and crash boundary.
