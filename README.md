# Metki — NFC tag library for iPhone

Personal iOS project by [Nikita Grigorchuk](https://github.com/nickonblack).

Metki reads and writes NFC tags and keeps a searchable library of saved tags. This repository is the first public snapshot of an existing project; it does not reproduce its earlier local development history.

## Features

- Read NDEF records and inspect tag details.
- Compose text, URL, contact, Wi-Fi, phone, SMS and location records.
- Organize saved tags with names, notes, shelves and photos.
- Import and export the library, merge changes and optionally synchronize through iCloud.
- Russian and English localization, App Intents and a home-screen widget.

## Structure

- `Metki/Domain`: record composition, validation, models, queries and localization.
- `Metki/NFC`: CoreNFC sessions, NDEF encoding and tag layout.
- `Metki/Persistence`: library storage, merging, iCloud files and tag secrets.
- `Metki/Features`: SwiftUI reading, writing and library screens.
- `MetkiTests`: validation, codec round-trips, compatibility and library behavior.
- `MetkiUITests`: library, navigation and localization scenarios.

## Build and run

Requires Xcode with the iOS SDK and iOS 17 or later. The project has no external package dependencies. Open `Metki.xcodeproj` and select the `Metki` scheme. `project.yml` is the source for the generated project; regenerate it with `xcodegen generate` when changing target settings.

The simulator supports the library and domain tests. NFC reading, writing and tag protection require a physical NFC-capable iPhone and compatible tags. For a device build, select your development team and configure your own bundle IDs, App Group and iCloud container. Update the corresponding identifiers in the entitlements, `LibraryFiles.swift` and `MetkiWidget.swift` together.

Run domain tests on an available simulator, for example:

```sh
xcodebuild test -project Metki.xcodeproj -scheme Metki \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MetkiTests
```

The 29 domain tests were checked with Xcode 27.1 on the iOS 26.2 simulator. Keep the normal simulator code signing enabled: the Keychain test requires a signed test host.

UI tests are in the same scheme and can be run from Xcode. NFC and iCloud behavior must also be checked on configured physical devices.

## Source availability

Published for portfolio review. Copyright 2026 Nikita Grigorchuk. All rights reserved; no open-source license is granted.
