# TachiyomiAZ iOS

An experimental, sideload-only iOS/iPadOS manga reader forked from
[Aidoku](https://github.com/Aidoku/Aidoku).

This branch is replacing Aidoku's source runtime with the official
OpenJDK/mobile Zero runtime for direct TachiyomiX JVM extension JARs, adding
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
- [x] TachiyomiX JAR sources as the iOS extension path (AIX/WASM and delegated
  source lists are disabled on iOS)
- [x] Core Mihon/TachiyomiX extension-lib 1.4–1.6 source compatibility
- [x] User-configured JAR repository installation and updates; no extension
  repositories are included or recommended by the app
- [x] Current `index.pb`/`index.json` stores and Mihon-compatible
  `mihon://extension-store?url=…` import links
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

The real-world extension checks do not embed a repository URL. Provide local
JAR paths to `Scripts/test-tachiyomix-1_4.sh` and
`Scripts/test-tachiyomix-1_6.sh`, or set
`TACHIYOMIAZ_EXTLIB_1_4_FIXTURE_URL` and `TACHIYOMIAZ_EXTLIB_1_6_FIXTURE_URL`.

```sh
TACHIAZ_JDK26_HOME=/path/to/jdk26 Scripts/build-openjdk-ios15.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk26 Scripts/bootstrap-suwayomi-compat.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk26 Scripts/build-mobile-shims.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk26 Scripts/build-extension-host.sh --test
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk26 Scripts/test-mobile-java-base.sh
```

The OpenJDK build installs matching iOS 15-targeted device and arm64 simulator
VMs and Java bundles. In Xcode, select an iPhone Simulator destination and run
the `Aidoku (iOS)` scheme; the build phase embeds the simulator bundle
automatically.

### GitHub Actions IPA

The **Build iPhone IPA** workflow runs after every push to `main` and can also
be started manually from the repository's **Actions** tab. When it succeeds,
download the `TachiyomiAZ-iOS-<commit>` artifact and extract the `.ipa` file.

The CI artifact is unsigned, so it cannot be installed by opening it directly
on an iPhone. Install it with AltStore, SideStore, or Sideloadly; that tool
signs the IPA with your Apple ID during installation. The workflow artifact is
kept for 14 days and includes a SHA-256 checksum.

The external extension-lib 1.4 and 1.6 runtime tests are optional in CI. Add
both `TACHIYOMIAZ_EXTLIB_1_4_FIXTURE_URL` and
`TACHIYOMIAZ_EXTLIB_1_6_FIXTURE_URL` as repository secrets to enable them;
the IPA build otherwise runs the self-contained extension-host tests and skips
the external fixtures.

## Contributing
The original application and reader are Aidoku work. JVM runtime changes in
this fork are described in `docs/JVM_RUNTIME.md`.

This repo (excluding translations) is licensed under [GPLv3](https://github.com/Aidoku/Aidoku/blob/main/LICENSE), but contributors must also sign the project [CLA](https://gist.github.com/Skittyblock/893952ff23f0df0e5cd02abbaddc2be9). Essentially, this just gives me (Skittyblock) the ability to distribute Aidoku via TestFlight/the App Store, but others must obtain an exception from me in order to do the same. Otherwise, GPLv3 applies and this code can be used freely as long as the modified source code is made available.

### Translations
Interested in translating Aidoku? We use [Weblate](https://hosted.weblate.org/engage/aidoku/) to crowdsource translations, so anyone can create an account and contribute!

Translations are licensed separately from the app code, under [Apache 2.0](https://spdx.org/licenses/Apache-2.0.html).
