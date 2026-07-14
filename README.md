<div align="center">

# MotionCut

### A serious video editor, built natively for mobile.

Cut, arrange, soundtrack, and export polished videos from a fast, touch-first timeline—on iOS and Android.

[![iOS](https://img.shields.io/badge/iOS_16+-000000?style=for-the-badge&logo=apple&logoColor=white)](#ios)
[![Android](https://img.shields.io/badge/Android_8+-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#android)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-F05138?style=for-the-badge&logo=swift&logoColor=white)](#architecture)
[![Kotlin](https://img.shields.io/badge/Jetpack_Compose-Native-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white)](#architecture)
[![License: MIT](https://img.shields.io/badge/License-MIT-F59E0B?style=for-the-badge)](LICENSE)

**Native SwiftUI. Native Kotlin. Open source.**

[Explore the code](#project-map) · [Run on iOS](#ios) · [Run on Android](#android) · [Contribute](#contributing)

</div>

---

## Create without leaving your phone

MotionCut is an open-source, mobile-first video editor. It combines a precise multi-clip timeline with native media frameworks, responsive previews, background rendering, music, and project management. There is no cross-platform UI layer: each app is designed for its platform from the ground up.

| Edit | Create | Deliver |
| :--- | :--- | :--- |
| Trim and arrange clips on a touch-first timeline | Combine footage, audio, and generated media | Render in the background and export to your library |
| Preview changes with native playback | Build short-form videos from an idea | Save projects and continue across sessions |
| Fine-tune timing and clip order | Work with local and remote assets | Share finished work anywhere |

## Why MotionCut

- **Actually native** — SwiftUI and AVFoundation on Apple platforms; Kotlin, Jetpack Compose, and Media3 on Android.
- **Built around the timeline** — editing interactions are the product, not an afterthought.
- **Private by default** — local editing remains on-device; connected services are explicit and configurable.
- **Hackable** — the platform apps live side by side, with readable models, services, and view models.
- **Production-minded** — background work, project persistence, authentication, subscriptions, and store metadata are already represented.

## Architecture

```text
MotionCut
├── CreatorAI/                 # Apple app — Swift + SwiftUI
│   ├── App/                   # Lifecycle and shared state
│   ├── Models/                # Projects, generations, clips, music
│   ├── Services/              # Playback, rendering, storage, APIs
│   ├── ViewModels/            # Feature state and orchestration
│   └── Views/VideoEditor/     # Preview, timeline, and editor tools
├── android/                   # Android app — Kotlin + Compose
│   └── app/src/main/java/.../
│       ├── models/            # Domain models
│       ├── services/          # Media, storage, and connected services
│       ├── viewmodels/        # Screen state
│       └── ui/editor/         # Native editor UI
└── worker/                    # Optional connected-service worker
```

Both clients follow a pragmatic MVVM-style structure. UI stays platform-native while the product concepts—projects, clips, generations, playback, and rendering—remain aligned across platforms.

## Get started

### iOS

Requirements: macOS, Xcode 15 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open CreatorAI.xcodeproj
```

Select the iOS scheme and run on an iOS 16+ simulator or device. Package dependencies are declared in [`project.yml`](project.yml) and resolve through Swift Package Manager.

### Android

Requirements: Android Studio, JDK 17, and an Android 8+ emulator or device.

```bash
cd android
./gradlew :app:assembleDebug
```

Open the `android` directory in Android Studio, let Gradle sync, and run the `app` configuration.

## Configuration

The repository does not need production credentials for contributors to inspect or develop the core editor. Connected features require your own local configuration:

1. Copy or create the platform-specific Firebase configuration locally.
2. Supply API endpoints and third-party keys through local configuration or CI secrets.
3. Create your own signing configuration for release builds.

Never commit API keys, service-account files, signing certificates, or store credentials. Before opening a pull request, check `git status` and review every staged file.

## Project map

- Apple editor UI: [`CreatorAI/Views/VideoEditor`](CreatorAI/Views/VideoEditor)
- Apple editor state: [`CreatorAI/ViewModels/VideoEditorViewModel.swift`](CreatorAI/ViewModels/VideoEditorViewModel.swift)
- Android editor UI: [`android/app/src/main/java/com/theholylabs/creator/ui/editor`](android/app/src/main/java/com/theholylabs/creator/ui/editor)
- Android editor state: [`android/app/src/main/java/com/theholylabs/creator/viewmodels/VideoEditorViewModel.kt`](android/app/src/main/java/com/theholylabs/creator/viewmodels/VideoEditorViewModel.kt)
- Build configuration: [`project.yml`](project.yml) and [`android/app/build.gradle.kts`](android/app/build.gradle.kts)

## Roadmap

- [ ] More timeline gestures and precision editing tools
- [ ] Text, captions, transitions, and visual effects
- [ ] Shared project interchange format across iOS and Android
- [ ] Deterministic render tests and sample projects
- [ ] Contributor-friendly demo mode with bundled media

## Contributing

Thoughtful issues and pull requests are welcome. Keep changes focused, follow the conventions of the platform you touch, and include build or test evidence. For UI work, screenshots or a short recording make reviews much easier.

If you are proposing a large feature, start with an issue so the interaction model and platform behavior can be discussed before implementation.

## License

MotionCut is available under the [MIT License](LICENSE).

<div align="center">

Built for editors who believe the best camera—and the best cutting room—is the one already in their hand.

</div>
