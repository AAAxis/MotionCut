# Creator AI - Native Swift/SwiftUI iOS App

Native iOS recreation of the Creator AI video generation app.

## Setup

### Option A: Using XcodeGen (Recommended)

1. Install XcodeGen: `brew install xcodegen`
2. Run: `cd ios-native && xcodegen generate`
3. Open `CreatorAI.xcodeproj` in Xcode
4. Add SPM dependencies via Xcode (File > Add Package Dependencies):
   - `https://github.com/supabase/supabase-swift.git` (2.0.0+)
   - `https://github.com/RevenueCat/purchases-ios-spm.git` (5.0.0+)
   - FFmpeg Kit: Follow https://github.com/arthenica/ffmpeg-kit for iOS integration
5. Build and run

### Option B: Manual Xcode Project

1. Open Xcode > Create New Project > iOS App > SwiftUI
2. Name it "CreatorAI", set deployment target to iOS 16.0
3. Delete the auto-generated ContentView.swift
4. Drag the entire `CreatorAI/` folder into the project navigator
5. Add SPM dependencies (same as above)
6. Build and run

## Configuration

Update these values before running:

- `APIService.swift` - Set your backend API URL
- `PurchaseService.swift` - Set your RevenueCat API key
- `UploadService.swift` - Set your Uploadcare public key

## Architecture

- **Pattern**: MVVM (Model-View-ViewModel)
- **UI**: SwiftUI (iOS 16+)
- **State**: @Observable / @Published + EnvironmentObject
- **Networking**: async/await + URLSession
- **Video**: AVFoundation + FFmpeg Kit
- **Subscriptions**: RevenueCat
- **Auth**: Supabase Swift SDK + Keychain

## Project Structure

```
CreatorAI/
├── App/           - App entry point, global state
├── Models/        - Data models (Clip, Generation, MusicTrack)
├── Services/      - API, Auth, Video rendering, File storage
├── Views/         - SwiftUI views organized by screen
├── ViewModels/    - Business logic for each screen
├── Theme/         - Color system (light/dark)
├── Extensions/    - View modifiers, Color helpers
└── Resources/     - Assets, Info.plist
```
