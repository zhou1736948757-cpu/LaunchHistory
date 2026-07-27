//
//  ThreeFingerDragEvent.swift
//  Launchpad_Back
//
//  三指拖动：模拟 macOS 系统"三指拖动"。
//  指针停在图标上时，三指滑动 = 拖动该图标（移动/生成文件夹/跨页），仅面板显示时生效。
//
//  本文件定义纯数据模型（事件枚举 + 通知名），不依赖 AppKit，方便复用与跨文件引用。
//  事件分发逻辑见 Services/ThreeFingerDragCoordinator.swift。
//

import CoreGraphics
import Foundation

/// 三指拖动 UI 事件（已完成坐标转换：location 为 SwiftUI `.global` 坐标空间，
/// 与 DragGesture 的 location 同空间）。由 Coordinator 通过通知派发给 ContentView。
enum ThreeFingerDragUIEvent {
    /// 开始拖动：用 NSEvent.mouseLocation 反查指针下图标作为 draggingItem。
    case begin(mouseLocation: CGPoint)
    /// 拖动位置更新（复用 ContentView 的 onDragChanged 逻辑）。
    case change(mouseLocation: CGPoint)
    /// 拖动结束：调 handleFloatingDrop 并清理状态（不进编辑模式）。
    case end
}

extension Notification.Name {
    /// 三指拖动 UI 事件通知：object 为 ThreeFingerDragUIEvent。
    static let threeFingerDragUIEvent = Notification.Name("threeFingerDragUIEvent")
}
