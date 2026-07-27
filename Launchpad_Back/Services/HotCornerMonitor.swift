//
//  HotCornerMonitor.swift
//  Launchpad_Back
//
//  Created on 2026-07-27.
//
//  屏幕热区监控服务
//  定时读取 NSEvent.mouseLocation，对照每个 NSScreen.frame 判断鼠标
//  是否停留在某个角落。停留约 0.3s 触发回调，触发后 1s 内冷却，
//  鼠标离开当前角落即重置停留计时，同一次停留不会连续重复触发。
//

import AppKit
import Foundation
import SwiftUI

/// 屏幕四个角落
enum HotCorner: String, Codable, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    /// 用于 UI 显示的本地化键（由本地化 agent 统一补 key）
    var localizedName: LocalizedStringKey {
        switch self {
        case .topLeft:     return "hot_corner_top_left"
        case .topRight:    return "hot_corner_top_right"
        case .bottomLeft:  return "hot_corner_bottom_left"
        case .bottomRight: return "hot_corner_bottom_right"
        }
    }
}

/// 热区监控器
///
/// 通过定时轮询 `NSEvent.mouseLocation`（全局鼠标坐标，不依赖窗口可见性）
/// 并比对所有 `NSScreen.frame` 的四个顶点来判断鼠标当前位于哪个角落。
///
/// 触发规则：
/// - 鼠标进入某个已启用角落后停留约 0.3s 触发一次 `onTrigger`。
/// - 触发后进入 1s 冷却期，期间即便仍停留在同一角落也不会重复触发。
/// - 鼠标离开当前角落即重置停留计时；再次进入开始新的停留计时。
/// - 默认不启用任何角落（`enabledCorners` 为空），`start()` 后也不会触发。
final class HotCornerMonitor {

    // MARK: - Configuration

    /// 角落判定阈值（像素）。鼠标距角落顶点小于此值即视为位于该角落。
    /// 多屏/高分屏下顶点判定容易因 1~2px 抖动而漏检，留出容差。
    private let cornerTolerance: CGFloat = 4.0

    /// 停留触发时长（秒）。鼠标在角落保持不动达到此时长后才触发。
    private let dwellDuration: TimeInterval = 0.3

    /// 触发后的冷却时间（秒），防止同一停留/抖动重复触发。
    private let cooldown: TimeInterval = 1.0

    /// 轮询间隔（秒）。`NSEvent.mouseLocation` 不提供变化通知，
    /// 需要靠定时器轮询；0.05s 既保证停留计时的分辨率，又不会过度占用 CPU。
    private let pollInterval: TimeInterval = 0.05

    // MARK: - Public State

    /// 启用的角落集合。默认为空（不启用任何角落）。
    /// 在主线程读写以保证与轮询回调的一致性。
    var enabledCorners: Set<HotCorner> = []

    /// 触发回调（始终在主线程派发）。
    var onTrigger: ((HotCorner) -> Void)?

    // MARK: - Private State

    /// 当前鼠标所在的（已启用）角落，nil 表示不在任何已启用角落。
    private var currentCorner: HotCorner?

    /// 当前停留开始时间（鼠标进入 currentCorner 的时刻）。
    private var dwellStartTime: Date?

    /// 上一次触发时间，用于冷却判定。
    private var lastTriggerTime: Date = .distantPast

    /// 轮询定时器。强引用以避免被 runloop 提前释放。
    private var pollTimer: Timer?

    /// 是否正在运行。
    private var isRunning = false

    // MARK: - Lifecycle

    deinit {
        stop()
    }

    /// 开始监控。重复调用安全（幂等）。
    func start() {
        guard !isRunning else { return }
        isRunning = true

        // 重置状态，避免上一次 stop 之间的残留
        currentCorner = nil
        dwellStartTime = nil
        lastTriggerTime = .distantPast

        let timer = Timer(timeInterval: pollInterval, target: self, selector: #selector(pollMouseLocation),
                          userInfo: nil, repeats: true)
        // 加入 common mode，保证在拖拽/模态等场景下也能持续轮询
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        Logger.info("HotCornerMonitor STARTED (enabled corners: \(enabledCorners.sorted { $0.rawValue < $1.rawValue }.map { $0.rawValue }.joined(separator: ",")))")
    }

    /// 停止监控。重复调用安全（幂等）。
    func stop() {
        guard isRunning else { return }
        isRunning = false

        // invalidate() 会自动把 timer 从所有 run loop mode 中移除，
        // 无需再显式调用 RunLoop.removeTimer。
        if let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }

        currentCorner = nil
        dwellStartTime = nil

        Logger.info("HotCornerMonitor STOPPED")
    }

    // MARK: - Polling

    /// 定时轮询鼠标位置并更新热区状态。
    @objc private func pollMouseLocation() {
        // mouseLocation 返回的是全局坐标（含多屏负坐标），单位为点。
        let location = NSEvent.mouseLocation

        // 找到鼠标所在的屏幕及其本地坐标
        guard let (screen, localPoint) = screenAndLocalPoint(for: location) else {
            // 鼠标不在任何屏幕上（理论上极少发生）：重置
            handleMouseLeftCurrentCorner()
            return
        }

        let detectedCorner = detectCorner(at: localPoint, in: screen)

        // 只关心“已启用”的角落
        let activeCorner: HotCorner? = {
            guard let corner = detectedCorner, enabledCorners.contains(corner) else { return nil }
            return corner
        }()

        if activeCorner == currentCorner {
            // 仍在同一角落：累加停留时间
            // 注意：activeCorner 和 currentCorner 可能同时为 nil（nil==nil 成立），
            // 此时不应触发 evaluateTrigger，必须 guard let 安全解包，避免强制解包崩溃。
            guard let corner = activeCorner else { return }
            updateDwell { [weak self] in
                self?.evaluateTrigger(corner: corner)
            }
        } else {
            // 切换到新角落（或离开）：重置停留计时
            handleMouseLeftCurrentCorner()
            if let corner = activeCorner {
                currentCorner = corner
                dwellStartTime = Date()
            }
        }
    }

    // MARK: - Corner Detection

    /// 在所有屏幕中找到包含全局坐标 `location` 的屏幕，并返回其本地坐标。
    /// 多屏场景下不同屏幕的 frame 可能存在负坐标（主屏左/下方的副屏）。
    private func screenAndLocalPoint(for location: NSPoint) -> (NSScreen, NSPoint)? {
        for screen in NSScreen.screens {
            let frame = screen.frame
            if location.x >= frame.minX && location.x <= frame.maxX,
               location.y >= frame.minY && location.y <= frame.maxY {
                // NSScreen 坐标系：原点在左下，frame 原点即屏幕左下角的全局坐标。
                // 本地坐标 = 全局坐标 - 屏幕原点
                let local = NSPoint(x: location.x - frame.minX, y: location.y - frame.minY)
                return (screen, local)
            }
        }
        return nil
    }

    /// 根据鼠标在屏幕内的本地坐标判断是否位于某个角落顶点附近。
    private func detectCorner(at point: NSPoint, in screen: NSScreen) -> HotCorner? {
        let width = screen.frame.width
        let height = screen.frame.height
        let tol = cornerTolerance

        let nearLeft   = point.x <= tol
        let nearRight  = point.x >= width - tol
        let nearBottom = point.y <= tol
        let nearTop    = point.y >= height - tol

        // NSScreen 本地坐标系 Y 轴向上：y≈0 是底部，y≈height 是顶部
        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearRight && nearBottom { return .bottomRight }
        return nil
    }

    // MARK: - Dwell & Trigger

    /// 鼠标离开当前角落（或鼠标不可用）时重置停留计时。
    private func handleMouseLeftCurrentCorner() {
        currentCorner = nil
        dwellStartTime = nil
    }

    /// 累加停留时间并在达到阈值时回调 `evaluate`。
    private func updateDwell(then evaluate: () -> Void) {
        guard let start = dwellStartTime else {
            dwellStartTime = Date()
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= dwellDuration {
            evaluate()
        }
    }

    /// 评估是否应触发回调（已满足停留时长，进一步检查冷却）。
    private func evaluateTrigger(corner: HotCorner) {
        let now = Date()

        // 冷却期内不重复触发（同一次停留只触发一次）
        if now.timeIntervalSince(lastTriggerTime) < cooldown {
            return
        }

        lastTriggerTime = now
        Logger.info("HotCornerMonitor triggered: \(corner.rawValue)")

        // 派发到主线程（轮询本就在主线程，这里保留一层 dispatch 保证调用者安全）
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?(corner)
        }
    }
}
