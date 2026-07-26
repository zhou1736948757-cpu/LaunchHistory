//
//  BackgroundView.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 2025/1/14.
//

import SwiftUI
import AppKit

/// Launchpad 風格的半透明背景（更接近原版）
struct BackgroundView: NSViewRepresentable {
    @AppStorage("backgroundOpacity") var opacity: Double = 0.85
    @AppStorage("windowMode") var windowMode: WindowMode = .fullscreen
    @AppStorage("blurEnabled") var blurEnabled: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true

        updateOpacity(for: visualEffectView)

        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        updateOpacity(for: nsView)
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
