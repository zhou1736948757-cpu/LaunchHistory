# Verify: LaunchHistory

Build & launch recipe for runtime verification of this macOS app.

## Build

```bash
cd /Users/mac/Downloads/Launchpad_Back
xcodebuild -project Launchpad_Back.xcodeproj -scheme Launchpad_Back \
  -configuration Release -derivedDataPath /tmp/lh_build build 2>&1 \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Product: `/tmp/lh_build/Build/Products/Release/LaunchHistory.app` (bundle name is
**LaunchHistory**, not Launchpad_Back). Debug build path: `/tmp/lh_build_debug`.

## Launch gotcha (IMPORTANT)

Launching the binary directly from a shell (`…/LaunchHistory.app/Contents/MacOS/LaunchHistory`)
crashes on startup with **EXC_BREAKPOINT / SIGTRAP (exit 133)** in
`HotCornerMonitor.pollMouseLocation()` — a **pre-existing** force-unwrap of
`activeCorner!` (line ~157) that fires when both `activeCorner` and `currentCorner`
are nil at a timer tick. This is NOT caused by multitouch/gesture changes; it is
an environment/session artifact of the direct-shell launch + missing TCC grants
for a fresh `/tmp` bundle. The installed `/Applications/LaunchHistory.app`
survives the same launch (it has prior LaunchServices registration + TCC).

Crash report location: `~/Library/Logs/DiagnosticReports/LaunchHistory-*.ips`
(format: line 1 = header JSON, line 2+ = body JSON with `faultingThread`).

To reach a runnable state for GUI interaction, prefer `open` over direct binary
launch, and grant Accessibility + Input Monitoring TCC to the build first:

```bash
open /tmp/lh_build/Build/Products/Release/LaunchHistory.app
```

## What needs real hardware

- **Four-finger pinch** (open/close panel) and **three-finger drag** (drag icons)
  both require real multitouch input via the private `MultitouchSupport.framework`.
  They cannot be exercised by clicking. Accessibility permission is required for
  the global gesture listener.
- Logs use `os_log` subsystem `com.Eric-Yang.Launchpad-Back`, ⦿ prefix. View with:
  `log show --predicate 'subsystem == "com.Eric-Yang.Launchpad-Back"' --info --last 5m`

## Coordinate note (for three-finger drag)

SwiftUI `.global` coordinate space on macOS == AppKit window-local coords
(origin at window lower-left, y-up). Verified empirically:
`NSWindow.convertPoint(fromScreen: window.frame.origin) == (0,0)`. So
`NSEvent.mouseLocation` → `window.convertPoint(fromScreen:)` lands in the same
space as `DragGesture(coordinateSpace: .global).location`. Both window modes use
`.fullSizeContentView`, so window coords == SwiftUI global coords.
