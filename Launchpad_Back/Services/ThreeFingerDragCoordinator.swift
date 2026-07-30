//
//  ThreeFingerDragCoordinator.swift
//  Launchpad_Back
//
//  集中处理三指拖动的坐标转换与事件分发。
//
//  三套坐标统一：
//  - NSEvent.mouseLocation      : 全局屏幕坐标（NSScreen，原点在主屏左下角，含多屏负坐标）
//  - AppKit 窗口坐标            : NSWindow 坐标空间（原点在窗口左下角，y 向上）
//  - SwiftUI Grid / DragGesture : `.global` 坐标空间
//
//  在 macOS 上，SwiftUI 的 `.global` 坐标空间 == AppKit 窗口坐标空间（原点在窗口左下角，
//  y 向上），前提是窗口使用 .fullSizeContentView 让内容铺满整个窗口（本项目的两种窗口模式
//  均满足：fullscreen 模式 borderless 全屏铺满；windowed/centered 模式开启
//  .fullSizeContentView + titlebarAppearsTransparent）。因此：
//      NSWindow.convertPoint(_:from:)  即可把 NSEvent.mouseLocation 转换为 SwiftUI 全局坐标。
//
//  拖动开始用 NSEvent.mouseLocation 反查指针下图标（不用三指触点中心），避免：
//  - 多屏/触控板绝对坐标系与屏幕坐标系不一致
//  - 触点中心落在图标边缘时命中错误
//  changed/ended 同样用鼠标位置，让浮动图标精确跟随指针。
//
//  分发方式：因 SwiftUI View 是值类型无法持有 weak 引用，Coordinator 通过 NotificationCenter
//  派发 ThreeFingerDragUIEvent，ContentView 订阅对应通知驱动状态机。
//

import AppKit
import CoreGraphics
import Foundation

/// 三指拖动协调器：把 MultitouchGestureRecognizer 的三指事件转换为 ContentView 可消费的事件。
///
/// 仅当面板显示时启用（由 AppDelegate 在 setupMultitouchPinch 时设置 window 并 install）。
final class ThreeFingerDragCoordinator {
    /// 主窗口弱引用：用于坐标转换。由 AppDelegate 在面板显示/隐藏时更新。
    weak var window: NSWindow?

    /// 是否已处于拖动中（避免重复 begin 或在异常 end 时漏清理）。
    private var isDragging = false

    /// 是否启用：仅当面板可见时为 true。由 AppDelegate 设置。
    private var enabled = false

    private let lock = NSLock()

    /// 接入 MultitouchGestureRecognizer 的三指事件。
    /// 由 AppDelegate 在 setupMultitouchPinch 里调用，把自身绑定为回调。
    func install() {
        MultitouchGestureRecognizer.shared.onThreeFingerDrag = { [weak self] event in
            self?.handle(event: event)
        }
        Logger.info("ThreeFingerDragCoordinator installed")
    }

    /// 卸载回调（AppDelegate 清理时调用）。
    func uninstall() {
        MultitouchGestureRecognizer.shared.onThreeFingerDrag = nil
        lock.lock()
        isDragging = false
        enabled = false
        lock.unlock()
        Logger.info("ThreeFingerDragCoordinator uninstalled")
    }

    /// 设置是否启用（面板显示/隐藏时由 AppDelegate 调用）。
    /// 隐藏时发送 .cancel 事件（而不是 .end）—避免执行 drop 逻辑把图标"放到"隐藏的面板网格中。
    func setEnabled(_ enabled: Bool) {
        lock.lock()
        let wasDragging = self.isDragging
        self.enabled = enabled
        if !enabled {
            self.isDragging = false
        }
        lock.unlock()

        // 面板隐藏时若仍在拖动，补发 cancel 通知，仅清理状态不执行 drop
        if wasDragging && !enabled {
            Logger.info("ThreeFingerDrag: disabled while dragging, emitting cancel")
            postEvent(.cancel)
        }
    }

    // MARK: - 事件处理

    private func handle(event: ThreeFingerDragEvent) {
        // 入口处统一拦截：必须 enabled 且 window 实际可见（orderOut 后 window 仍存在但不可见）
        lock.lock()
        let currentEnabled = enabled
        let windowVisible = window?.isVisible ?? false
        lock.unlock()
        Logger.info("⦿ [DIAG] handle event=\(event) enabled=\(currentEnabled) windowVisible=\(windowVisible)")
        guard currentEnabled, windowVisible else { return }
        switch event {
        case .began:
            beginDrag()
        case .changed:
            // 仅在已开始拖动时派发 change，避免在未启用前误触发
            lock.lock()
            let dragging = isDragging
            lock.unlock()
            guard dragging else { return }
            changeDrag()
        case .ended:
            lock.lock()
            let dragging = isDragging
            lock.unlock()
            guard dragging else { return }
            endDrag()
        }
    }

    private func beginDrag() {
        lock.lock()
        guard enabled, window != nil else {
            lock.unlock()
            return
        }
        // 防御：若上一次拖动未正常结束（例如错过 ended），先复位
        if isDragging {
            isDragging = false
            lock.unlock()
            postEvent(.end)
            lock.lock()
        }
        isDragging = true
        lock.unlock()

        let screenLocation = NSEvent.mouseLocation
        guard let globalLocation = convertToSwiftUIGlobal(screenLocation) else {
            Logger.warning("ThreeFingerDrag: begin 但坐标转换失败，忽略")
            lock.lock()
            isDragging = false
            lock.unlock()
            return
        }

        Logger.info("ThreeFingerDrag: begin at mouse=\(screenLocation) -> global=\(globalLocation)")
        postEvent(.begin(mouseLocation: globalLocation))
    }

    private func changeDrag() {
        let screenLocation = NSEvent.mouseLocation
        guard let globalLocation = convertToSwiftUIGlobal(screenLocation) else { return }
        postEvent(.change(mouseLocation: globalLocation))
    }

    private func endDrag() {
        lock.lock()
        isDragging = false
        lock.unlock()
        Logger.info("ThreeFingerDrag: end")
        postEvent(.end)
    }

    // MARK: - 通知派发

    private func postEvent(_ event: ThreeFingerDragUIEvent) {
        // 通知在主线程派发（MultitouchGestureRecognizer 的 onThreeFingerDrag 已切主线程，
        // 这里再保险一次 ensure main）
        let block = {
            NotificationCenter.default.post(name: .threeFingerDragUIEvent,
                                            object: event)
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    // MARK: - 坐标转换

    /// 将 NSEvent.mouseLocation（全局屏幕坐标）转换为 SwiftUI `.global` 坐标空间。
    ///
    /// 关键：currentGridLayout / DragGesture(.global) / .position() 用的都是
    /// "SwiftUI 局部坐标"——原点在窗口左上角，y 向下。
    /// 而 NSWindow.convertPoint(fromScreen:) 返回的是 AppKit 窗口坐标——原点左下，y 向上。
    /// 两者 y 轴方向相反，会导致三指拖动行号算反（第一行变最后一行）、浮动图标位置镜像。
    ///
    /// 正确做法：以窗口左上角为原点，y 向下，把屏幕坐标转成相对窗口左上角的偏移。
    private func convertToSwiftUIGlobal(_ screenLocation: CGPoint) -> CGPoint? {
        guard let window = window else { return nil }
        // 1. 屏幕坐标 → AppKit 窗口坐标（原点左下，y 向上）
        let winPoint = window.convertPoint(fromScreen: screenLocation)
        // 2. AppKit 窗口坐标(左下原点,y向上) → SwiftUI 局部坐标(左上原点,y向下)
        //    y 翻转：swiftY = windowHeight - appKitY
        let swiftY = window.frame.height - winPoint.y
        return CGPoint(x: winPoint.x, y: swiftY)
    }
}
