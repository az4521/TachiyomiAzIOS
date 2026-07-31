# TachiyomiAZ iOS

An experimental, sideload-only iOS/iPadOS manga reader forked from
[Aidoku](https://github.com/Aidoku/Aidoku).

This branch is replacing Aidoku's source runtime with the official
OpenJDK/mobile Zero runtime for direct Keiyoushi JVM extension JARs, adding
Mihon/TachiyomiAZ backup
import, and using a Material Design 1-inspired navigation drawer.

The Java host, JNI boundary, JAR validation/loading, pinned Suwayomi source
API/AndroidCompat layer, repository installer, browse/search/filter/details/
chapters/pages/image operations, preferences, web-login cookies, and backup
decoder are implemented and tested against real extension-lib 1.4 and 1.6
JARs on a java.base-style runtime matching the iOS image. The complete stack
still needs an Xcode simulator build on macOS. See
[`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md).

## Features
- [x] No ads
- [x] Keiyoushi JAR sources as the iOS extension path (AIX/WASM and delegated
  source lists are disabled on iOS)
- [x] Core Mihon/Keiyoushi extension-lib 1.4–1.6 source compatibility
- [x] User-configured JAR repository installation and updates; no extension
  repositories are included or recommended by the app
- [x] Mihon/TachiyomiAZ `.tachibk` import
- [x] Online reading through external sources
- [x] Downloads
- [x] Tracker integration (AniList, MyAnimeList)

## Installation

This fork is not distributed through TestFlight or the App Store. Build it with
Xcode for either an iOS Simulator or a physical iOS device. Sideloading is only
needed for a physical device. Its bundle identifier is
`app.tachiyomiaz.TachiyomiAZ`, so it can coexist with Aidoku.

Before the first build:

```sh
Scripts/bootstrap-openjdk-ios.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk21 Scripts/bootstrap-suwayomi-compat.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk21 Scripts/build-mobile-shims.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk21 Scripts/build-extension-host.sh --test
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk21 Scripts/test-mobile-java-base.sh
```

The OpenJDK bootstrap installs separate device and simulator Java bundles. In
Xcode, select an iPhone Simulator destination and run the `Aidoku (iOS)`
scheme; the build phase embeds the simulator bundle automatically. The
nightly workflow also uploads the unsigned universal simulator `.app` as a zip
before producing the sideloadable device IPA.

To install a downloaded simulator artifact after booting a simulator:

```sh
unzip TachiyomiAZ-iOS_Simulator-*.zip
xcrun simctl install booted Aidoku.app
xcrun simctl launch booted app.tachiyomiaz.TachiyomiAZ
```

## Contributing
The original application and reader are Aidoku work. JVM runtime changes in
this fork are described in `docs/JVM_RUNTIME.md`.

This repo (excluding translations) is licensed under [GPLv3](https://github.com/Aidoku/Aidoku/blob/main/LICENSE), but contributors must also sign the project [CLA](https://gist.github.com/Skittyblock/893952ff23f0df0e5cd02abbaddc2be9). Essentially, this just gives me (Skittyblock) the ability to distribute Aidoku via TestFlight/the App Store, but others must obtain an exception from me in order to do the same. Otherwise, GPLv3 applies and this code can be used freely as long as the modified source code is made available.

### Translations
Interested in translating Aidoku? We use [Weblate](https://hosted.weblate.org/engage/aidoku/) to crowdsource translations, so anyone can create an account and contribute!

Translations are licensed separately from the app code, under [Apache 2.0](https://spdx.org/licenses/Apache-2.0.html).
