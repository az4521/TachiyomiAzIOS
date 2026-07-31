# TachiAZ iOS

An experimental, sideload-only iOS/iPadOS manga reader forked from
[Aidoku](https://github.com/Aidoku/Aidoku).

This branch is replacing Aidoku's source runtime with the official
OpenJDK/mobile Zero runtime for direct Keiyoushi JVM extension JARs, adding
Mihon/TachiyomiAZ backup
import, and using a Material Design 1-inspired navigation drawer.

The JVM work is under active development. The Java host, JNI boundary, JAR
validation/loading, and backup decoder are implemented and tested off-device;
the full Mihon extension API/Android compatibility surface still needs
physical-device validation and expansion. See
[`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md).

## Features
- [x] No ads
- [x] Aidoku WASM sources during the compatibility transition
- [ ] Full Mihon/Keiyoushi JAR source compatibility
- [x] Online reading through external sources
- [x] Downloads
- [x] Tracker integration (AniList, MyAnimeList)

## Installation

This fork is not distributed through TestFlight or the App Store. Build it with
Xcode for a physical iOS device and sideload the resulting app.

Before the first device build:

```sh
Scripts/bootstrap-openjdk-ios.sh
TACHIAZ_BUILD_JAVA_HOME=/path/to/jdk8 Scripts/build-extension-host.sh --test
TACHIAZ_BUILD_JAVA_HOME=/path/to/jdk8 Scripts/test-keiyoushi-asurascans.sh
```

## Contributing
The original application and reader are Aidoku work. JVM runtime changes in
this fork are described in `docs/JVM_RUNTIME.md`.

This repo (excluding translations) is licensed under [GPLv3](https://github.com/Aidoku/Aidoku/blob/main/LICENSE), but contributors must also sign the project [CLA](https://gist.github.com/Skittyblock/893952ff23f0df0e5cd02abbaddc2be9). Essentially, this just gives me (Skittyblock) the ability to distribute Aidoku via TestFlight/the App Store, but others must obtain an exception from me in order to do the same. Otherwise, GPLv3 applies and this code can be used freely as long as the modified source code is made available.

### Translations
Interested in translating Aidoku? We use [Weblate](https://hosted.weblate.org/engage/aidoku/) to crowdsource translations, so anyone can create an account and contribute!

Translations are licensed separately from the app code, under [Apache 2.0](https://spdx.org/licenses/Apache-2.0.html).
