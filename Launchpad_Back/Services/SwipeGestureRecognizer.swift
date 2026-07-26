//
//  SwipeGestureRecognizer.swift
//  Launchpad_Back
//
//  Created on 2026-07-25.
//

import AppKit

/// 滑动方向枚举
enum SwipeDirection {
    case up      // 向上滑动
    case down    // 向下滑动
    case left    // 向左滑动
    case right   // 向右滑动
}

/// 滑动手势识别器
class SwipeGestureRecognizer {

    // MARK: - Properties

    /// 最小滑动距离阈值
    private var minimumSwipeDistance: CGFloat = 50.0

    /// 滑动回调闭包
    private var swipeCallback: ((SwipeDirection) -> Void)?

    /// 手势监听器
    private var localMonitor: Any?

    /// 跟踪当前手势状态
    private var isTracking = false

    /// 跟踪起始点
    private var startPoint: NSPoint?

    /// 跟踪当前点
    private var currentPoint: NSPoint?

    // MARK: - Initialization

    /// 初始化滑动手势识别器
    /// - Parameters:
    ///   - minimumSwipeDistance: 最小滑动距离阈值，默认为50.0
    ///   - callback: 手势触发时的回调函数
    init(minimumSwipeDistance: CGFloat = 50.0, callback: @escaping (SwipeDirection) -> Void = { _ in }) {
        self.minimumSwipeDistance = minimumSwipeDistance
        self.swipeCallback = callback
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// 设置滑动回调
    /// - Parameter callback: 滑动触发时的回调函数
    func setSwipeCallback(_ callback: @escaping (SwipeDirection) -> Void) {
        self.swipeCallback = callback
    }

    /// 开始监听手势
    func start() {
        // 监听手势事件
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.gesture]) { [weak self] event in
            self?.handleSwipeEvent(event)
            return event
        }
    }

    /// 停止监听手势
    func stop() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isTracking = false
        startPoint = nil
        currentPoint = nil
    }

    // MARK: - Private Methods

    /// 处理滑动手势事件
    /// - Parameter event: 手势事件
    private func handleSwipeEvent(_ event: NSEvent) {
        guard event.type == .swipe else { return }

        let phase = event.phase

        // NSEvent.Phase 是 OptionSet，使用条件判断而非 switch
        if phase.contains(.began) {
            // 开始追踪手势
            isTracking = true
            startPoint = event.locationInWindow
            currentPoint = event.locationInWindow
        } else if phase.contains(.changed) {
            // 更新当前点
            currentPoint = event.locationInWindow
        } else if phase.contains(.ended) {
            // 手势结束，分析方向
            if let start = startPoint, let current = currentPoint {
                analyzeSwipeDirection(from: start, to: current)
            }

            // 重置追踪状态
            isTracking = false
            startPoint = nil
            currentPoint = nil
        } else if phase.contains(.cancelled) {
            // 手势取消，重置状态
            isTracking = false
            startPoint = nil
            currentPoint = nil
        }
        // .mayBegin, .stationary 等阶段不处理
    }

    /// 分析滑动方向
    /// - Parameters:
    ///   - start: 起始点
    ///   - current: 当前点
    private func analyzeSwipeDirection(from start: NSPoint, to current: NSPoint) {
        let deltaX = current.x - start.x
        let deltaY = current.y - start.y
        let absDeltaX = abs(deltaX)
        let absDeltaY = abs(deltaY)

        // 检查是否达到最小滑动距离
        guard max(absDeltaX, absDeltaY) >= minimumSwipeDistance else {
            return
        }

        // 判断主要滑动方向
        if absDeltaX > absDeltaY {
            // 水平滑动
            if deltaX > 0 {
                notifySwipe(direction: .right)
            } else {
                notifySwipe(direction: .left)
            }
        } else {
            // 垂直滑动
            if deltaY > 0 {
                notifySwipe(direction: .down)
            } else {
                notifySwipe(direction: .up)
            }
        }
    }

    /// 通知手势触发
    /// - Parameter direction: 滑动方向
    private func notifySwipe(direction: SwipeDirection) {
        DispatchQueue.main.async { [weak self] in
            self?.swipeCallback?(direction)
        }
    }
}

// MARK: - NSEvent Phase Extension

extension NSEvent.Phase {
    /// 获取手势阶段描述
    var gesturePhase: String {
        // NSEvent.Phase 是 OptionSet，使用条件判断而非 switch
        var parts: [String] = []
        if contains(.began) { parts.append("began") }
        if contains(.stationary) { parts.append("stationary") }
        if contains(.changed) { parts.append("changed") }
        if contains(.ended) { parts.append("ended") }
        if contains(.cancelled) { parts.append("cancelled") }
        if contains(.mayBegin) { parts.append("mayBegin") }
        return parts.isEmpty ? "unknown" : parts.joined(separator: ",")
    }
}