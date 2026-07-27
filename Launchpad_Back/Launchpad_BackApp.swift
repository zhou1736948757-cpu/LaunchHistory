//
//  Launchpad_BackApp.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 6/21/25.
//

import SwiftUI
import AppKit
import Carbon

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    static let windowModeChanged = Notification.Name("windowModeChanged")
    static let gesturesChanged = Notification.Name("gesturesChanged")
    static let layoutSettingsChanged = Notification.Name("layoutSettingsChanged")
    static let mainWindowDidActivate = Notification.Name("mainWindowDidActivate")
}

@main
struct Launchpad_BackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class LaunchpadWindow: NSWindow {
    var onCloseRequested: (() -> Void)?

    // 全屏 borderless 模式下，NSWindow 默认 canBecomeKeyWindow 返回 NO，
    // 导致窗口收不到键盘事件、TapGesture/DragGesture 事件分发异常、
    // localMonitor（手势）也不触发。这里强制返回 YES 修复以上问题。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        if let onCloseRequested {
            onCloseRequested()
            return
        }

        super.performClose(sender)
    }

    override func close() {
        if let onCloseRequested {
            onCloseRequested()
            return
        }

        super.close()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaultWindowSize = NSSize(width: 1000, height: 700)
    private var globalHotKeyRef: EventHotKeyRef?
    private var globalHotKeyHandlerRef: EventHandlerRef?
    private let globalHotKeySignature: OSType = 0x4C50424B // "LPBK"
    private let globalHotKeyID: UInt32 = 1

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var swipeGestureRecognizer: SwipeGestureRecognizer?
    private var multitouchStarted = false
    private let hotCornerMonitor = HotCornerMonitor()
    /// 三指拖动协调器：仅面板显示时启用。
    private let threeFingerDragCoordinator = ThreeFingerDragCoordinator()
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.info("Application did finish launching")
        createMainWindowIfNeeded()
        registerGlobalHotKey()
        setupGestureRecognizers()
        setupHotCornerMonitor()
        showMainWindow()
        requestAccessibilityPermissionIfNeeded()

        NotificationCenter.default.addObserver(self, selector: #selector(showSettingsWindow),      name: .openSettingsRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reconfigureMainWindow),   name: .windowModeChanged,      object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildGestureRecognizers), name: .gesturesChanged,       object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMainWindowActivated), name: .mainWindowDidActivate,  object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateHotCornerEnabledCorners), name: .hotCornerSettingsChanged, object: nil)
    }

    /// 初始化热区（触发角）监控：从 UserDefaults 读取启用的角落，挂上触发回调并启动。
    private func setupHotCornerMonitor() {
        hotCornerMonitor.enabledCorners = currentEnabledHotCorners()
        hotCornerMonitor.onTrigger = { [weak self] _ in
            // 触发角命中即显示主窗口（不论当前是否已可见，showMainWindow 幂等安全）
            Logger.info("Hot corner triggered - showing window")
            self?.showMainWindow()
        }
        hotCornerMonitor.start()
    }

    /// 当前在 UserDefaults 中启用的触发角集合。
    private func currentEnabledHotCorners() -> Set<HotCorner> {
        let defaults = UserDefaults.standard
        var enabled: Set<HotCorner> = []
        if defaults.bool(forKey: "hotCornerTopLeft")     { enabled.insert(.topLeft) }
        if defaults.bool(forKey: "hotCornerTopRight")    { enabled.insert(.topRight) }
        if defaults.bool(forKey: "hotCornerBottomLeft")  { enabled.insert(.bottomLeft) }
        if defaults.bool(forKey: "hotCornerBottomRight") { enabled.insert(.bottomRight) }
        return enabled
    }

    /// 设置面板改动触发角时，更新 monitor 的 enabledCorners。
    /// notification.object 为新的 Set<HotCorner>。
    @objc func updateHotCornerEnabledCorners(_ notification: Notification) {
        let corners: Set<HotCorner>
        if let provided = notification.object as? Set<HotCorner> {
            corners = provided
        } else {
            corners = currentEnabledHotCorners()
        }
        hotCornerMonitor.enabledCorners = corners
        Logger.info("Hot corner enabled corners updated: \(corners.map { $0.rawValue }.sorted().joined(separator: ","))")
    }

    /// 检查并请求辅助功能权限（手势全局监听需要）
    private func requestAccessibilityPermissionIfNeeded() {
        let trusted = AXIsProcessTrusted()
        Logger.info("Accessibility trusted: \(trusted)")
        if !trusted {
            // 弹出系统权限请求对话框
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options)
        }
    }

    /// 重建手势识别器（设置面板切换手势开关时调用）
    @objc func rebuildGestureRecognizers() {
        cleanupGestureRecognizers()
        let preferences = UserPreferencesManager.shared.preferences
        guard preferences.gesturesEnabled else { return }
        if let window = mainWindow {
            setupSwipeGesture(for: window)
        }
        setupMultitouchPinch()
        // 重建后若面板仍可见，重新启用三指拖动协调器：
        // cleanupGestureRecognizers -> uninstall 会把 enabled 置 false，
        // setupMultitouchPinch -> install 只重设回调，不复位 enabled。
        // 若不在此补 enabled=true，面板保持显示时三指拖动会失效直到下次显示/隐藏。
        if let window = mainWindow, window.isVisible {
            threeFingerDragCoordinator.window = window
            threeFingerDragCoordinator.setEnabled(true)
        }
        Logger.info("Gesture recognizers rebuilt")
    }

    /// 主窗口激活时关闭设置面板
    @objc func handleMainWindowActivated() {
        if let sw = settingsWindow {
            sw.close()
            settingsWindow = nil
            Logger.info("Settings window closed due to main window activation")
        }
    }

    /// 打开设置面板（全局唯一）
    @objc func showSettingsWindow() {
        // 无论是否可见，只要对象存在就复用，防止多窗口
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .preferredColorScheme(.dark)

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // 设置窗口必须高于主窗口（.screenSaver = 1000），否则被全屏面板遮挡
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.delegate = self
        self.settingsWindow = window
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.info("Application will terminate")
        unregisterGlobalHotKey()
        cleanupGestureRecognizers()
        hotCornerMonitor.stop()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        clampedFrameSize(for: sender, proposedSize: frameSize)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === mainWindow else {
            return
        }

        let clampedSize = clampedFrameSize(for: window, proposedSize: window.frame.size)
        guard window.frame.size != clampedSize else {
            return
        }

        let adjustedOrigin = NSPoint(
            x: window.frame.maxX - clampedSize.width,
            y: window.frame.origin.y
        )
        window.setFrame(NSRect(origin: adjustedOrigin, size: clampedSize), display: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // 设置窗口关闭：恢复主窗口的全屏层级配置
        if window === settingsWindow {
            settingsWindow = nil
            if let main = mainWindow {
                configureMainWindow(main)
            }
            Logger.info("Settings window closed, restored main window level")
            return
        }

        // 主窗口关闭
        if window === mainWindow {
            mainWindow = nil
            // 三指拖动：窗口已销毁，清除引用并禁用，避免坐标转换命中已释放窗口
            threeFingerDragCoordinator.setEnabled(false)
            threeFingerDragCoordinator.window = nil
            Logger.info("Main window closed")
        }
    }

    /// 主窗口成为 key window 时关闭设置面板
    /// 解决：打开设置面板→点击 Launch 面板→ESC 退出 Launch 后设置面板残留
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === mainWindow else { return }
        if let sw = settingsWindow {
            sw.close()
            settingsWindow = nil
            Logger.info("Settings window closed: main window became key")
        }
    }
    
    func hideMainWindow() {
        guard let window = mainWindow else {
            Logger.warning("No main window found")
            return
        }

        // 三指拖动：面板隐藏前先禁用，避免拖动进行中面板被隐藏导致状态悬挂
        threeFingerDragCoordinator.setEnabled(false)

        // 隐藏前先降回 .normal 级别，确保系统合成层彻底释放，
        // 避免与 Traffic Lights Plus 等插件冲突（全屏透明蒙层残留问题）
        window.level = .normal
        window.orderOut(nil)

        // 同步关闭设置面板（主面板隐藏时，设置面板没有存在意义）
        if let sw = settingsWindow {
            sw.close()
            settingsWindow = nil
        }

        logWindowState(window, context: "hide")
        Logger.info("Window hidden")
    }

    func closeMainWindow() {
        guard mainWindow != nil else {
            Logger.warning("No main window found")
            return
        }

        hideMainWindow()
    }
    
    func showMainWindow() {
        createMainWindowIfNeeded()

        guard let window = mainWindow else {
            Logger.warning("No main window found")
            return
        }

        configureMainWindow(window)
        ensureWindowIsOnScreen(window)

        // 三指拖动：面板显示时绑定窗口并启用。
        // 必须在 configureMainWindow 之后（窗口 frame/层级已定，坐标转换才准确）。
        threeFingerDragCoordinator.window = window
        threeFingerDragCoordinator.setEnabled(true)
        
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        // borderless 全屏窗口有时首次 makeKey 不生效（key=false），
        // 延迟重试一次确保成为 key window，否则点击/键盘事件分发异常。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let w = self.mainWindow, !w.isKeyWindow else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            Logger.info("Re-attempted makeKey for main window")
        }

        logWindowState(window, context: "show")
        Logger.info("Window shown")
    }
    
    func toggleMainWindowVisibility() {
        guard let window = mainWindow else {
            showMainWindow()
            return
        }
        
        logWindowState(window, context: "toggle")
        
        if shouldHideWindow(window) {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }
    
    private func createMainWindowIfNeeded() {
        guard mainWindow == nil else { return }
        
        let rootView = ContentView()
            .preferredColorScheme(.dark)
        
        let hostingController = NSHostingController(rootView: rootView)
        let window = LaunchpadWindow(
            contentRect: NSRect(origin: .zero, size: defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.setContentSize(defaultWindowSize)
        window.setFrame(NSRect(origin: .zero, size: defaultWindowSize), display: false)
        window.contentMinSize = GridLayoutManager.minimumWindowContentSize
        window.minSize = minimumWindowFrameSize(for: window)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isRestorable = false
        window.onCloseRequested = { [weak self] in
            self?.hideMainWindow()
        }
        window.delegate = self
        window.center()
        
        self.mainWindow = window
        
        configureMainWindow(window)
        Logger.info("Main window created")
    }
    
    /// 註冊全局快捷鍵 (Command + L)
    private func registerGlobalHotKey() {
        unregisterGlobalHotKey()
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                return appDelegate.handleGlobalHotKeyEvent(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &globalHotKeyHandlerRef
        )
        
        guard handlerStatus == noErr else {
            Logger.error("Failed to install global hot key handler: \(handlerStatus)")
            return
        }
        
        let hotKeyID = EventHotKeyID(signature: globalHotKeySignature, id: globalHotKeyID)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &globalHotKeyRef
        )
        
        guard registerStatus == noErr else {
            if let handler = globalHotKeyHandlerRef {
                RemoveEventHandler(handler)
                globalHotKeyHandlerRef = nil
            }
            Logger.error("Failed to register global hot key: \(registerStatus)")
            return
        }
        
        Logger.info("Global hot key registered successfully")
    }
    
    /// 取消註冊全局快捷鍵
    private func unregisterGlobalHotKey() {
        if let hotKeyRef = globalHotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            globalHotKeyRef = nil
        }
        
        if let handlerRef = globalHotKeyHandlerRef {
            RemoveEventHandler(handlerRef)
            globalHotKeyHandlerRef = nil
        }
        
        Logger.info("Global hot key unregistered")
    }
    
    private func handleGlobalHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else {
            Logger.error("Failed to read global hot key event: \(status)")
            return status
        }
        
        guard hotKeyID.signature == globalHotKeySignature, hotKeyID.id == globalHotKeyID else {
            return OSStatus(eventNotHandledErr)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.toggleMainWindowVisibility()
        }
        
        return noErr
    }
    
    private func configureMainWindow(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        behavior.insert(.moveToActiveSpace)
        behavior.insert(.fullScreenAuxiliary)
        window.collectionBehavior = behavior
        window.isReleasedWhenClosed = false

        // 读取用户设置的窗口模式（与设置面板/BackgroundView 使用同一个 key）
        let mode = WindowMode(rawValue: UserDefaults.standard.string(forKey: "windowMode") ?? "")
            ?? .fullscreen

        switch mode {
        case .fullscreen:
            // 全屏覆盖：铺满整个屏幕（含灵动岛/菜单栏区域），上下都有背景，视觉更完整
            // UI 内容通过 ContentView 的 topPadding 下移，避开灵动岛
            window.level = .screenSaver
            window.styleMask = [.borderless, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovable = false
            // 窗口保持透明（isOpaque 默认 false）：NSVisualEffectView 的 .behindWindow
            // 模糊 + 背景不透明度设置才能正常生效，且 borderless 窗口才能成为 key window
            // （isOpaque=true 会导致 borderless 窗口无法成为 key，影响键盘/搜索）。
            // 点击穿透问题由 ContentView 的 Color.clear 捕获层兜底处理空白点击；
            // 非 tap 事件穿透若仍有问题，后续可加透明 NSView 拦截层。
            if let screen = NSScreen.main {
                window.setFrame(screen.frame, display: true)
            }
        case .windowed, .centered:
            // 浮动窗口：保留标题栏样式，可移动可缩放
            window.level = .floating
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovable = true
        }

        if window.contentLayoutRect.width < GridLayoutManager.minimumWindowContentSize.width ||
            window.contentLayoutRect.height < GridLayoutManager.minimumWindowContentSize.height {
            window.setContentSize(defaultWindowSize)
            Logger.info("Corrected zero-sized window frame")
        }
    }

    /// 重新应用窗口模式配置（设置面板切换窗口模式时调用）
    @objc func reconfigureMainWindow() {
        guard let window = mainWindow else { return }
        configureMainWindow(window)
        Logger.info("Main window reconfigured after window mode change")
    }

    private func minimumWindowFrameSize(for window: NSWindow) -> NSSize {
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: GridLayoutManager.minimumWindowContentSize)).size
        return NSSize(width: ceil(frameSize.width), height: ceil(frameSize.height))
    }

    private func clampedFrameSize(for window: NSWindow, proposedSize: NSSize) -> NSSize {
        let minimumFrameSize = minimumWindowFrameSize(for: window)
        return NSSize(
            width: max(proposedSize.width, minimumFrameSize.width),
            height: max(proposedSize.height, minimumFrameSize.height)
        )
    }
    
    private func ensureWindowIsOnScreen(_ window: NSWindow) {
        let availableFrames = NSScreen.screens.map(\.visibleFrame)
        let isOnAnyScreen = availableFrames.contains { $0.intersects(window.frame) }
        
        guard !isOnAnyScreen, let targetFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return
        }
        
        let origin = CGPoint(
            x: targetFrame.midX - (window.frame.width / 2),
            y: targetFrame.midY - (window.frame.height / 2)
        )
        let centeredFrame = NSRect(origin: origin, size: window.frame.size)
        window.setFrame(centeredFrame, display: false)
        Logger.info("Repositioned window onto active screen")
    }
    
    private func shouldHideWindow(_ window: NSWindow) -> Bool {
        let appIsForeground = NSApplication.shared.isActive && !NSApplication.shared.isHidden
        let windowIsActuallyVisible = window.isVisible && window.occlusionState.contains(.visible)
        return appIsForeground && windowIsActuallyVisible
    }
    
    private func logWindowState(_ window: NSWindow, context: String) {
        let screenFrame = window.screen?.frame.debugDescription ?? "nil"
        let occlusion = window.occlusionState.rawValue
        Logger.info(
            "Window state [\(context)] visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) mini=\(window.isMiniaturized) frame=\(window.frame.debugDescription) screen=\(screenFrame) level=\(window.level.rawValue) occlusion=\(occlusion)"
        )
    }

    // MARK: - Gesture Recognition

    private func setupGestureRecognizers() {
        guard let window = mainWindow else {
            Logger.warning("Cannot setup gesture recognizers: no main window")
            return
        }

        let preferences = UserPreferencesManager.shared.preferences
        guard preferences.gesturesEnabled else {
            Logger.info("Gesture recognition disabled")
            return
        }

        Logger.info("Setting up gesture recognizers")
        setupSwipeGesture(for: window)
        setupMultitouchPinch()
    }

    /// 启动全局四指捏合识别（基于私有 MultitouchSupport.framework）
    /// 全局监听，不依赖窗口是否显示，面板隐藏时也能唤醒
    private func setupMultitouchPinch() {
        guard !multitouchStarted else { return }
        MultitouchGestureRecognizer.shared.setCallback { [weak self] direction in
            self?.handleMultitouchPinch(direction: direction)
        }
        // 三指拖动：把回调接到 coordinator，坐标转换后通过通知派发给 ContentView。
        // 注意：coordinator.window 与 enabled 仅在面板显示时设置，
        // 面板隐藏时三指事件被丢弃，不影响四指捏合。
        threeFingerDragCoordinator.install()
        MultitouchGestureRecognizer.shared.start()
        multitouchStarted = true
    }

    private func setupSwipeGesture(for window: NSWindow) {
        swipeGestureRecognizer = SwipeGestureRecognizer(minimumSwipeDistance: 50.0)
        swipeGestureRecognizer?.setSwipeCallback { [weak self] direction in
            self?.handleSwipeGesture(direction: direction)
        }
        swipeGestureRecognizer?.start()
        Logger.info("Swipe gesture recognizer added")
    }

    private func cleanupGestureRecognizers() {
        swipeGestureRecognizer?.stop()
        swipeGestureRecognizer = nil
        if multitouchStarted {
            // 三指拖动：先禁用并卸载回调，再停掉底层设备
            threeFingerDragCoordinator.setEnabled(false)
            threeFingerDragCoordinator.uninstall()
            MultitouchGestureRecognizer.shared.stop()
            multitouchStarted = false
        }
        Logger.info("Gesture recognizers cleaned up")
    }

    /// 处理四指捏合（全局，面板隐藏时也能触发）
    private func handleMultitouchPinch(direction: MultitouchPinchDirection) {
        let preferences = UserPreferencesManager.shared.preferences
        guard preferences.gesturesEnabled else { return }

        switch direction {
        case .pinchIn:
            // 四指捏拢 = 打开面板
            Logger.info("Multitouch pinch IN - showing window")
            showMainWindow()
        case .pinchOut:
            // 四指张开 = 关闭面板
            Logger.info("Multitouch pinch OUT - hiding window")
            hideMainWindow()
        }
    }

    private func handleSwipeGesture(direction: SwipeDirection) {
        let preferences = UserPreferencesManager.shared.preferences
        Logger.info("Swipe gesture detected with direction: \(direction)")

        switch direction {
        case .up:
            if preferences.openGesture == .swipeUp {
                Logger.info("Swipe up - showing window")
                showMainWindow()
            }
        case .down:
            if preferences.closeGesture == .swipeDown {
                Logger.info("Swipe down - hiding window")
                hideMainWindow()
            }
        case .left:
            if preferences.closeGesture == .swipeLeft {
                Logger.info("Swipe left - hiding window")
                hideMainWindow()
            }
        case .right:
            if preferences.openGesture == .swipeRight {
                Logger.info("Swipe right - showing window")
                showMainWindow()
            }
        }
    }
    
    deinit {
        Logger.debug("AppDelegate deinitialized")
    }
}
