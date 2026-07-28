# LaunchHistory

> A high-performance native Launchpad replacement for macOS 15+, built with SwiftUI + AppKit.

**[English](./README.md) | [繁體中文](./README_zh-TW.md) | [简体中文](./README_zh-CN.md)**

<div align="center">
  <img src="./Example.png" alt="LaunchHistory Interface" width="800"/>
</div>

## ✨ Features

### Core Functionality
- **Four-Finger Pinch** to open/close launcher (system-level gesture recognition via MultitouchSupport framework)
- **⌘+L Global Hotkey** toggle from anywhere
- **Hot Corners** activation support
- **Three-Finger Drag** to reorder apps or create folders (AppKit NSPanel overlay, 15.6% CPU average)
- **Long Press** (0.2s) to enter edit mode with wiggle animation
- **Search** with real-time filtering by app name, bundle ID, or path
- **Folders** with drag-to-create, expand/collapse, drag-out support
- **Custom App Sources** beyond /Applications (configurable paths)

### UI & UX
- **Horizontal Paging** or **Vertical Scrolling** layout modes
- **Background Blur** with adjustable transparency
- **Blue Insertion Indicator** shows exact drop position during drag
- **App Hiding** from launcher (without uninstalling)
- **Custom Renaming** for any app
- **Multi-language** support (English, 简体中文, 繁體中文) following system locale

### Performance
- **CPU Usage**: 0.1% idle, ~15% during three-finger drag (optimized from 23.6%)
- **Memory**: 160-190MB stable
- **AppKit NSPanel** for drag overlay (bypasses SwiftUI re-renders)
- **30ms throttle** on drop target calculation (reduces from 125-250Hz to ~33Hz)
- **Icon Cache** with async loading and NSWorkspace fallback

## 🎯 Why This Project?

macOS 15 (Sequoia/Tahoe) removed certain Launchpad customization options. This project restores full control:
- Gesture-based activation without relying on Dock
- Native performance (no Electron/web wrappers)
- Full drag-and-drop reordering with visual feedback
- Extensible folder system

## 📦 Installation

### Option 1: Build from Source

**Requirements**: Xcode 16+, macOS 15+

```bash
git clone https://github.com/EricYang801/Launchpad_Back.git
cd Launchpad_Back
open Launchpad_Back.xcodeproj
```

Build and run with `⌘+R`, or:

```bash
xcodebuild -project Launchpad_Back.xcodeproj -scheme Launchpad_Back -configuration Release build
```

### Option 2: Download Release (Coming Soon)

Pre-built `.app` bundles will be available on the [Releases](../../releases) page.

## 🚀 Usage

1. **Launch** the app — it runs in the menu bar
2. **Open launcher**:
   - Press `⌘+L` (global hotkey)
   - Four-finger pinch on trackpad
   - Move cursor to configured hot corner
3. **Reorder apps**:
   - **Long press** (0.2s) any icon → wiggle mode → drag to new position
   - **Three-finger drag** directly on any icon (no long press needed)
4. **Create folders**: Drag one app onto another
5. **Search**: Start typing when launcher is open
6. **Settings**: Click gear icon in top-right corner

## ⚙️ Configuration

Access settings via the gear icon in launcher:

- **Layout Mode**: Horizontal Paging / Vertical Scrolling
- **Background Blur**: Adjust transparency (0-100%)
- **Search Bar**: Show/hide
- **Hot Corners**: Choose activation corners
- **App Sources**: Add custom directories beyond `/Applications`
- **Hidden Apps**: Manage visibility
- **Language**: Auto-detects system locale

## 🛠️ Architecture

- **SwiftUI** for main UI (grid layout, folder views, settings)
- **AppKit** for:
  - Global hotkey (`CGEventTap`)
  - Floating drag overlay (`NSPanel` at `.screenSaver` level)
  - Hot corner monitoring (`NSEvent.addGlobalMonitorForEvents`)
- **MultitouchSupport.framework** (private) for four-finger pinch and three-finger drag detection
- **UserDefaults** for persistent storage (app order, folders, hidden apps, settings)

### Key Performance Optimizations
1. **NSPanel Overlay**: Drag icon rendered in separate window, bypasses SwiftUI body re-evaluation (125-250Hz → 0Hz on main view)
2. **Drop Target Throttle**: 30ms interval (250Hz → 33Hz calculation frequency)
3. **Icon Cache**: Shared `AppIconCache` with async loading, `NSWorkspace.icon(forFile:)` fallback
4. **Gesture Coordinator**: Direct callbacks to SwiftUI state, no polling

## 🧪 Testing

Run unit tests:

```bash
xcodebuild test -scheme Launchpad_Back -destination 'platform=macOS'
```

Test coverage:
- Icon resolution (direct path, symlink, metadata, fallback)
- Icon cache (canonical paths, concurrent requests, deduplication)
- Folder CRUD operations and order persistence
- Search matching (name, bundle ID, path)
- Pagination bounds and slicing
- Layout reset behavior

## 📝 Roadmap

- [ ] App uninstall from launcher (move to Trash)
- [ ] Customizable grid size (rows × columns)
- [ ] iCloud sync for layout/folders
- [ ] Nested folders (currently single-level)
- [ ] Keyboard navigation (arrow keys)

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

GPL-3.0 License. See [LICENSE](./LICENSE) for details.

## 🙏 Credits

- **MultitouchSupport.framework** reverse-engineering community
- **macOS gestures** inspired by iOS/iPadOS SpringBoard
- **AppKit + SwiftUI** hybrid approach for performance

---

**Keywords**: Launchpad alternative, macOS launcher, SwiftUI AppKit, four-finger gesture, three-finger drag, app launcher macOS 15, Sequoia launcher replacement
