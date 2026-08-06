//
//  BackgroundView.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 2025/1/14.
//

import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Launchpad 風格的半透明背景（更接近原版）
struct BackgroundView: NSViewRepresentable {
    @AppStorage("backgroundOpacity") var opacity: Double = 0.85
    @AppStorage("windowMode") var windowMode: WindowMode = .fullscreen
    @AppStorage("blurEnabled") var blurEnabled: Bool = true

    func makeNSView(context: Context) -> FreezableBlurView {
        let container = FreezableBlurView()
        updateOpacity(for: container.blurView)

        return container
    }

    func updateNSView(_ nsView: FreezableBlurView, context: Context) {
        updateOpacity(for: nsView.blurView)
    }

    private func updateOpacity(for visualEffectView: NSVisualEffectView) {
        let adjustedOpacity = opacity * 0.3

        if let layer = visualEffectView.layer {
            // 全屏模式下使用更深的模糊材质
            if blurEnabled {
                visualEffectView.material = windowMode == .fullscreen ? .fullScreenUI : .popover
            } else {
                visualEffectView.material = .windowBackground
            }
            layer.backgroundColor = NSColor.black.withAlphaComponent(adjustedOpacity).cgColor
        }
    }
}

/// 可凍結的模糊背景容器：
/// 面板可見時，將桌面壁紙高斯模糊成靜態圖，取代實時模糊，
/// 避免 NSVisualEffectView 每幀重算全屏模糊拖累 GPU（滑動頁面卡頓的來源之一）。
/// 面板隱藏時恢復實時模糊。
final class FreezableBlurView: NSView {
    let blurView = NSVisualEffectView()

    private var snapshotView: NSImageView?
    private var observers: [NSObjectProtocol] = []
    private var freezePending = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.autoresizingMask = [.width, .height]
        blurView.frame = bounds
        addSubview(blurView)
        registerWindowObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func registerWindowObservers() {
        let nc = NotificationCenter.default
        // 面板為 key window 時視為顯示，離開 key 狀態視為隱藏
        observers.append(nc.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, notification.object as? NSWindow === self.window else { return }
            self.scheduleFreeze()
        })
        observers.append(nc.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, notification.object as? NSWindow === self.window else { return }
            self.unfreeze()
        })
    }

    /// 窗口顯示後延遲一小段時間再凍結，確保窗口已上屏、bounds 有效
    private func scheduleFreeze() {
        guard !isFrozen, !freezePending else { return }
        freezePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.freezePending = false
            guard let self, !self.isFrozen,
                  let win = self.window, win.isVisible,
                  self.bounds.width > 0, self.bounds.height > 0 else { return }
            self.freeze()
        }
    }

    private var isFrozen: Bool { snapshotView != nil }

    private func freeze() {
        guard !isFrozen else { return }
        guard let image = Self.captureBackgroundSnapshot(screen: window?.screen ?? NSScreen.main) else {
            // 壁紙讀取失敗（如純色桌面）：降級為實時模糊，不影響功能
            Logger.warning("Background freeze failed (no readable wallpaper?): keep live blur")
            return
        }

        let iv = NSImageView(frame: bounds)
        iv.image = image
        // 壁紙已按螢幕尺寸生成，填滿即可（避免小數點差異造成的留邊）
        iv.imageScaling = .scaleAxesIndependently
        iv.autoresizingMask = [.width, .height]
        addSubview(iv, positioned: .above, relativeTo: blurView)
        snapshotView = iv
        blurView.isHidden = true
        Logger.debug("Background frozen to static snapshot")
    }

    private func unfreeze() {
        guard isFrozen else { return }
        blurView.isHidden = false
        snapshotView?.removeFromSuperview()
        snapshotView = nil
        Logger.debug("Background unfrozen, live blur restored")
    }

    /// 讀取桌面壁紙並高斯模糊為靜態背景圖（不再截屏，無需螢幕錄製權限）
    private static func captureBackgroundSnapshot(screen: NSScreen?) -> NSImage? {
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        // 目標像素尺寸 = 螢幕點數 × backingScale（Retina 下保持銳利）
        let scale = max(screen.backingScaleFactor, 1)
        let dstW = max(1, Int(screen.frame.width * scale))
        let dstH = max(1, Int(screen.frame.height * scale))

        // 按桌面「填充」方式縮放：放大到覆蓋整個螢幕後居中裁剪，避免留邊
        let cover = max(Double(dstW) / Double(cgImage.width), Double(dstH) / Double(cgImage.height))
        let ciImage = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(scaleX: cover, y: cover))
        let cropX = max(0, (ciImage.extent.width - Double(dstW)) / 2)
        let cropY = max(0, (ciImage.extent.height - Double(dstH)) / 2)
        let cropped = ciImage.cropped(to: CGRect(x: cropX, y: cropY, width: Double(dstW), height: Double(dstH)))

        // 邊緣 clamp，避免高斯模糊在邊緣產生的透明漸變
        let clamped = cropped.clampedToExtent()
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(clamped, forKey: kCIInputImageKey)
        // 模糊半徑：近似 fullScreenUI 材質的觀感
        filter?.setValue(30.0, forKey: kCIInputRadiusKey)
        guard let blurred = filter?.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let output = context.createCGImage(blurred, from: cropped.extent) else { return nil }

        // 以點數為單位返回（像素由 backingScale 決定），與視圖尺寸一一對應
        return NSImage(cgImage: output, size: screen.frame.size)
    }
}

/// 漸變背景覆蓋層
struct GradientOverlay: View {
    @AppStorage("backgroundOpacity") var opacity: Double = 0.85
    @AppStorage("windowMode") var windowMode: WindowMode = .fullscreen

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.black.opacity(opacity * 0.2),
                Color.black.opacity(opacity * 0.1),
                Color.black.opacity(opacity * 0.2)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// 組合背景視圖
struct LaunchpadBackgroundView: View {
    var body: some View {
        ZStack {
            BackgroundView()
            GradientOverlay()
        }
        .ignoresSafeArea()
    }
}
