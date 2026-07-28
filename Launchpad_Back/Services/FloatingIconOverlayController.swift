//
//  FloatingIconOverlayController.swift
//  Launch_historyreview
//
//  【性能优化·AppKit NSPanel方案】浮动拖拽图标：独立 NSPanel overlay 窗口。
//
//  用独立 NSPanel（非激活、borderless、透明）替代向 NSHostingView 添加子视图的方案。
//  好处：完全不受 SwiftUI 视图层级影响，z-order 由 window level 保证，坐标转换简单。
//
//  125-250Hz 位置更新只调 NSPanel.setFrameOrigin()，不触发 SwiftUI 任何状态。
//

import AppKit
import UniformTypeIdentifiers

@MainActor
final class FloatingIconOverlayController {
    // MARK: - 单例（避免通过 NSApp.delegate as? AppDelegate 访问的 cast 问题）
    static let shared = FloatingIconOverlayController()

    // MARK: - 属性

    /// 主窗口弱引用（坐标转换用）
    weak var mainWindow: NSWindow?

    /// 独立浮动图标窗口（NSPanel，非激活、透明）
    private var overlayPanel: NSPanel?

    /// 图标视图
    private var iconView: NSImageView?

    /// App 名称 label
    private var labelView: NSTextField?

    /// 图标大小（pt）
    private let iconSize: CGFloat = 60

    // MARK: - 生命周期

    /// 绑定主窗口引用（showMainWindow 时调用，用于坐标转换）
    func install(in window: NSWindow) {
        mainWindow = window
        Logger.info("FloatingIconOverlayController: bound to window")
    }

    func uninstall() {
        end()
        overlayPanel = nil
        mainWindow = nil
    }

    // MARK: - 拖动控制

    /// 开始拖动：创建/显示 NSPanel overlay，在 SwiftUI 坐标处居中
    func begin(icon: NSImage?, appName: String, at swiftUIPoint: CGPoint) {
        guard let mainWindow = mainWindow else {
            Logger.warning("FloatingIconOverlayController.begin: mainWindow 未绑定")
            return
        }

        // 首次创建 panel（之后复用）
        if overlayPanel == nil {
            createPanel()
        }
        guard let panel = overlayPanel else { return }

        // 更新图标
        if let iv = iconView {
            iv.image = icon ?? NSWorkspace.shared.icon(for: UTType.applicationBundle)
        }

        // 更新 label
        labelView?.stringValue = appName

        // 定位 panel 并显示
        setFrameOrigin(swiftUIPoint, window: mainWindow)
        panel.orderFront(nil)
        Logger.info("FloatingIconOverlayController: begin '\(appName)' at=\(swiftUIPoint)")
    }

    /// 位置更新（高频，125-250Hz）：只更新 NSPanel.frameOrigin，不触发 SwiftUI
    func updateLocation(_ swiftUIPoint: CGPoint) {
        guard let mainWindow = mainWindow, let panel = overlayPanel, panel.isVisible else { return }
        // 直接设 frame origin，无动画，接近零开销
        setFrameOrigin(swiftUIPoint, window: mainWindow)
    }

    /// 结束拖动：隐藏 panel
    func end() {
        overlayPanel?.orderOut(nil)
        Logger.debug("FloatingIconOverlayController: end")
    }

    // MARK: - 创建 Panel

    private func createPanel() {
        let totalH = iconSize + 4 + 20   // 图标 + 间距 + label 高度
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: iconSize, height: totalH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true   // 不拦截鼠标事件

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: iconSize, height: totalH))
        contentView.wantsLayer = true
        panel.contentView = contentView

        // 图标
        let iv = NSImageView(frame: NSRect(x: 0, y: 24, width: iconSize, height: iconSize))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 14
        iv.layer?.masksToBounds = true
        iv.layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        iv.layer?.shadowRadius = 8
        iv.layer?.shadowOpacity = 1
        iv.layer?.shadowOffset = .zero
        contentView.addSubview(iv)
        iconView = iv

        // label（在图标下方）
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.frame = NSRect(x: -30, y: 0, width: iconSize + 60, height: 20)
        label.wantsLayer = true
        label.layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        label.layer?.shadowRadius = 2
        label.layer?.shadowOpacity = 1
        contentView.addSubview(label)
        labelView = label

        overlayPanel = panel
        Logger.info("FloatingIconOverlayController: NSPanel created")
    }

    // MARK: - 坐标转换

    /// SwiftUI 坐标（窗口左上原点，y向下）→ NSPanel origin（屏幕左下原点，y向上）
    /// 步骤：SwiftUI → AppKit 窗口坐标 → 屏幕坐标 → panel origin（icon居中）
    private func setFrameOrigin(_ swiftUIPoint: CGPoint, window: NSWindow) {
        guard let panel = overlayPanel else { return }
        let totalH = iconSize + 4 + 20

        // 1. SwiftUI(左上,y下) → AppKit window(左下,y上)
        let appKitWindowY = window.frame.height - swiftUIPoint.y
        let windowPoint = NSPoint(x: swiftUIPoint.x, y: appKitWindowY)

        // 2. AppKit window → screen
        let screenPoint = window.convertPoint(toScreen: windowPoint)

        // 3. panel origin：使图标中心对准鼠标
        let originX = screenPoint.x - iconSize / 2
        let originY = screenPoint.y - iconSize - 4  // label 在图标下方，icon 上方对鼠标

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        panel.contentView?.frame.size = NSSize(width: iconSize, height: totalH)
    }
}
