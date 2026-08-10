# TachiyomiAZ for iOS

TachiyomiAZ iOS is a sideload-focused manga reader for iPhone and iPad. It
runs Tachiyomi/TachiyomiX JVM extension JARs through a bundled OpenJDK runtime
and an iOS Android-compatibility layer.

The app does not include extension repositories or a built-in catalogue of
third-party sources. Users choose and add their own compatible repository.

## LEGAL NOTICE: 
TachiyomiAZ™ is intended to be used for viewing EMAILS and FREE doujins only, I do not condone using this app to access pirated copyrighted material, and by installing TachiyomiAZ™ you agree not to use the application for this purpose. Installing any extensions designed to access anything but EMAIL and FREELY AVAILABLE FAN WORKS is strongly discouraged, cuz I don't wanna get sued. any mention of manga within the application, source code, or this readme is referring only to doujinshi manga.

For legal purposes this is an EMAIL AND FREE DOUJINSHI READER APP, NOT TO BE USED TO ILLEGALLY ACCESS COPYRIGHTED MATERIAL

plz don't sue me

## Features

- Tachiyomi and TachiyomiX extension-lib 1.4–1.6 compatibility
- User-provided `index.pb` and `index.json` extension repositories
- Browse, latest, search, source filters, extension settings, and web login
- Library categories, filters, updates, reading history, and background updates
- Chapter downloads with a persistent queue and background progress
- Reader modes, tracking, and configurable appearance
- Mihon and TachiyomiAZ `.tachibk` import and export
- iOS 15 or newer on iPhone and iPad
- Apple-silicon iOS Simulator support for local development

## Install with AltStore or SideStore

Add the TachiyomiAZ iOS source:

**[Add to AltStore](altstore://source?url=https%3A%2F%2Fraw.githubusercontent.com%2Faz4521%2FTachiyomiAZiOS%2Frefs%2Fheads%2Faltstore%2Fapps.json)**

Source URL:

```text
https://raw.githubusercontent.com/az4521/TachiyomiAZiOS/refs/heads/altstore/apps.json
```

The source follows successful builds from `main` and provides the current
unsigned IPA. AltStore or SideStore signs it with your Apple ID during
installation. The app is not distributed through the App Store or TestFlight.

You can also download `TachiyomiAZ-iOS.ipa` from the repository's
[nightly release](https://github.com/az4521/TachiyomiAZiOS/releases/tag/nightly)
and install it using AltStore, SideStore, or Sideloadly.

## Add an extension repository

Open **Extensions**, add a repository URL, and use a compatible `index.pb` or
`index.json` endpoint. No repository is configured by default.

Repository links can also be opened with the Mihon-compatible deep link:

```text
mihon://extension-store?url=<percent-encoded-repository-url>
```

Only add repositories whose contents you trust. Extensions execute code inside
the bundled JVM compatibility environment and can make network requests.


## Backups

TachiyomiAZ iOS uses `.tachibk` as its backup format. Restoring a backup merges
it into the existing library. Existing read chapters stay read, while chapters
marked read by the backup are promoted to read.

Create or restore backups from **Settings → Backups**.

---

## How Suwayomi is used

TachiyomiAZ iOS uses part of
[Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) as its JVM
compatibility foundation. It does **not** launch a Suwayomi web server or use
Suwayomi's web interface, library database, reader, or download manager.

During the build,
[`Scripts/bootstrap-suwayomi-compat.sh`](Scripts/bootstrap-suwayomi-compat.sh)
checks out the pinned Suwayomi-Server commit
[`eb2dc0b`](https://github.com/Suwayomi/Suwayomi-Server/tree/eb2dc0b19a9571b27c02bebc5c883e404b7bd7fb),
applies a small
[iOS runtime patch](Scripts/patches/suwayomi-ios-runtime.patch), and copies an
allowlisted set of build outputs and runtime dependencies into the app. The
important pieces are Suwayomi's Tachiyomi source API, `AndroidCompat`, Android
API stubs, configuration support, and their required JVM libraries.

At runtime, those JARs run inside the bundled OpenJDK VM. TachiyomiAZ's Java
extension host initializes the Suwayomi application, AndroidCompat,
configuration, and Koin modules without starting the server entry point. Our
iOS-specific compatibility shims provide or replace mobile APIs such as the
Android main looper and native graphics/text behavior. The extension host then
invokes Tachiyomi extension source methods and returns their models to the
native Swift app.

The native UI, extension repository management, library, backup support,
downloads, and reader are implemented by TachiyomiAZ iOS. Thank you to the
Suwayomi contributors for the compatibility work that makes JVM extensions
practical outside Android. The pinned Suwayomi-Server code is distributed
under the
[Mozilla Public License 2.0](https://github.com/Suwayomi/Suwayomi-Server/blob/eb2dc0b19a9571b27c02bebc5c883e404b7bd7fb/LICENSE),
while TachiyomiAZ iOS is distributed under GPLv3. See their respective
repositories for source and full license terms.

## Build from source

Requirements:

- macOS with Xcode
- JDK 24 for building the mobile OpenJDK runtime
- JDK 21 or newer for the extension host and compatibility components

Prepare the bundled runtime and Java host:

```sh
Scripts/build-openjdk-ios15.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk24 Scripts/bootstrap-suwayomi-compat.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk24 Scripts/build-mobile-shims.sh
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk24 Scripts/build-extension-host.sh --test
TACHIYOMIAZ_BUILD_JAVA_HOME=/path/to/jdk24 Scripts/test-mobile-java-base.sh
```

Open the Xcode project, select the iOS application target, and build for an
iOS 15+ device. For the simulator, use an Apple-silicon iPhone or iPad Simulator
destination. Physical-device installation requires code signing or a sideloading
tool.

The **Build iPhone IPA** GitHub Actions workflow builds an unsigned IPA after
each push to `main`. The workflow caches the OpenJDK runtime, validates the JVM
host, publishes the rolling nightly IPA, and updates the AltStore source.

External extension fixtures are optional in CI. Configure both
`TACHIYOMIAZ_EXTLIB_1_4_FIXTURE_URL` and
`TACHIYOMIAZ_EXTLIB_1_6_FIXTURE_URL` as repository secrets to enable those
tests.

More implementation details are available in
[`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md) and
[`docs/JVM_RUNTIME.md`](docs/JVM_RUNTIME.md).

## Support and development

- [GitHub issues](https://github.com/az4521/TachiyomiAZiOS/issues)
- [Discord](https://discord.gg/mihon)
- [Ko-fi](https://ko-fi.com/az4521)

Contributions are welcome through pull requests. Please keep source-specific
workarounds out of the shared compatibility layer when an Android API or
extension-library behavior can be implemented generically.

## License

The application source is distributed under the [GNU GPLv3](LICENSE).
Translations and third-party components may carry their own licenses; consult
their accompanying notices before redistribution.

## Credit

Thank you to the Aidoku, Suwayomi, Mihon, and OpenJDK teams for

- [Aidoku, the starting point from which this app was developed, using only the non-proprietary parts of the Aidoku app](https://github.com/Aidoku/Aidoku)
- [Suwayomi-Server, for the android compatibility library that powers the app's extension system](https://github.com/Suwayomi/Suwayomi-Server)
- [TachiyomiX, the standard interface used by extensions and the format used by extension repositories](https://github.com/mihonapp/tachiyomix)
- [OpenJDK Mobile Zero-Assembler, the java virtual machine that allows running Suwayomi and TachiyomiX extensions on iOS](https://github.com/openjdk/mobile)
