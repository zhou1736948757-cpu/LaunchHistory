//
//  MultitouchGestureRecognizer.swift
//  Launch_historyreview
//
//  全局四指捏合手势识别器（基于私有 MultitouchSupport.framework）
//
//  原理：通过 dlopen 加载 /System/Library/PrivateFrameworks/MultitouchSupport.framework，
//        用 MTRegisterContactFrameCallback 注册回调，拿到每一帧所有手指的坐标，
//        自己计算"四指向中心收缩/张开"来判断捏合。
//        这是全局接口，不依赖 app 是否前台，面板隐藏时也能唤醒。
//
//  代价：私有 API，macOS 系统更新可能破坏；需"输入监控"权限；不能上 Mac App Store。
//  参考：MIT 开源项目 okruts/macos-gesture-launcher
//

import AppKit
import Foundation

// MARK: - 捏合方向

enum MultitouchPinchDirection {
    case pinchIn   // 四指捏拢（向中心收缩）→ 打开面板
    case pinchOut  // 四指张开（向外扩散）→ 关闭面板
}

// MARK: - 私有框架数据结构

/// 触控板上的点（归一化或绝对坐标）
struct MTPoint {
    var x: Float
    var y: Float
}

struct MTReadout {
    var position: MTPoint
    var velocity: MTPoint
}

/// 单个手指的原始触控数据（与 MultitouchSupport.framework 的 MTTouch 结构对齐）
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32        // 0 = 未触摸, 非0 = 活跃
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout   // 归一化坐标 (0.0–1.0)
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout     // 绝对(像素)坐标
    var zero2: (Int32, Int32)
    var density: Float
}

// MARK: - 私有框架函数类型（C 调用约定）

typealias MTDeviceRef = UnsafeMutableRawPointer

typealias MTDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFArray>?
typealias MTRegisterContactFrameCallbackFunc =
    @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
typealias MTUnregisterContactFrameCallbackFunc =
    @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
typealias MTDeviceStartFunc = @convention(c) (MTDeviceRef, Int32) -> Void
typealias MTDeviceStopFunc = @convention(c) (MTDeviceRef, Int32) -> Void

/// 接触帧回调签名：(device, touches指针, 数量, 时间戳, 帧号) -> Int32
typealias MTContactCallbackFunction =
    @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) -> Int32

// MARK: - 私有框架加载器

/// dlopen 加载 MultitouchSupport.framework，解析所需符号
enum MultitouchSupport {
    nonisolated(unsafe) static var handle: UnsafeMutableRawPointer?
    nonisolated(unsafe) static var deviceCreateList: MTDeviceCreateListFunc?
    nonisolated(unsafe) static var registerCallback: MTRegisterContactFrameCallbackFunc?
    nonisolated(unsafe) static var unregisterCallback: MTUnregisterContactFrameCallbackFunc?
    nonisolated(unsafe) static var deviceStart: MTDeviceStartFunc?
    nonisolated(unsafe) static var deviceStop: MTDeviceStopFunc?

    private static var loaded = false

    /// 加载私有框架。成功返回 true。
    @discardableResult
    static func load() -> Bool {
        if loaded { return handle != nil }

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let opened = dlopen(path, RTLD_NOW) else {
            Logger.error("MultitouchSupport: dlopen 失败 path=\(path)")
            loaded = true
            return false
        }
        handle = opened
        loaded = true

        deviceCreateList = loadSymbol("MTDeviceCreateList", as: MTDeviceCreateListFunc.self)
        registerCallback = loadSymbol("MTRegisterContactFrameCallback",
                                      as: MTRegisterContactFrameCallbackFunc.self)
        unregisterCallback = loadSymbol("MTUnregisterContactFrameCallback",
                                        as: MTUnregisterContactFrameCallbackFunc.self)
        deviceStart = loadSymbol("MTDeviceStart", as: MTDeviceStartFunc.self)
        deviceStop = loadSymbol("MTDeviceStop", as: MTDeviceStopFunc.self)

        let ok = deviceCreateList != nil && registerCallback != nil
                 && deviceStart != nil && deviceStop != nil
        Logger.info("MultitouchSupport loaded: \(ok) (createList=\(deviceCreateList != nil) reg=\(registerCallback != nil) start=\(deviceStart != nil) stop=\(deviceStop != nil))")
        return ok
    }

    private static func loadSymbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let h = handle, let symbol = dlsym(h, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
}

// MARK: - 手势识别器

/// 全局四指捏合识别器
final class MultitouchGestureRecognizer {
    static let shared = MultitouchGestureRecognizer()

    /// 触发捏合所需的最少手指数（四指捏合）
    private let targetFingerCount = 4
    /// 捏合幅度阈值：相对质心距离变化超过此值才算有效捏合
    private let pinchThreshold: Double = 0.18
    /// 冷却时间（秒），防止同一手势重复触发
    /// 0.2s：面板打开后可立即再捏合关闭，避免被冷却卡住
    private let cooldown: TimeInterval = 0.2

    private var callback: (MultitouchPinchDirection) -> Void
    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray?

    /// 当前手势的追踪状态
    private var startDistance: Double = 0
    private var lastDistance: Double = 0
    private var trackingFingerCount: Int = 0
    private var lastTriggerTime: TimeInterval = 0

    private let queue = DispatchQueue(label: "com.LaunchHistory.multitouch")

    private init() {
        callback = { _ in }
    }

    /// 设置捏合回调
    func setCallback(_ cb: @escaping (MultitouchPinchDirection) -> Void) {
        callback = cb
    }

    /// 启动监听
    func start() {
        guard MultitouchSupport.load() else {
            Logger.error("MultitouchGestureRecognizer: 私有框架加载失败，无法启动")
            return
        }
        guard devices.isEmpty else { return }

        guard let createList = MultitouchSupport.deviceCreateList,
              let listRef = createList() else {
            Logger.error("MultitouchGestureRecognizer: MTDeviceCreateList 返回空")
            return
        }
        let list = listRef.takeUnretainedValue()
        deviceList = list  // 持有 CFArray 生命周期

        let count = CFArrayGetCount(list)
        for index in 0..<count {
            let value = CFArrayGetValueAtIndex(list, index)
            let device = unsafeBitCast(value, to: MTDeviceRef.self)
            devices.append(device)
            MultitouchSupport.registerCallback?(device, mtContactCallback)
            MultitouchSupport.deviceStart?(device, 0)
        }
        Logger.info("MultitouchGestureRecognizer STARTED，注册了 \(devices.count) 个触控设备")
    }

    /// 停止监听
    func stop() {
        for device in devices {
            MultitouchSupport.unregisterCallback?(device, mtContactCallback)
            MultitouchSupport.deviceStop?(device, 0)
        }
        devices.removeAll()
        deviceList = nil
        Logger.info("MultitouchGestureRecognizer STOPPED")
    }

    // MARK: - C 回调（必须是自由函数，因为 @convention(c)）

    /// 接触帧回调：每帧所有手指的原始数据
    private let mtContactCallback: MTContactCallbackFunction = { device, touches, count, timestamp, frame in
        guard count > 0 else { return 0 }
        let typed = touches.assumingMemoryBound(to: MTTouch.self)
        let buffer = UnsafeBufferPointer(start: typed, count: Int(count))

        // 收集活跃手指（state != 0）的归一化坐标
        var points: [(Double, Double)] = []
        for touch in buffer {
            if touch.state != 0 {
                points.append((Double(touch.normalized.position.x),
                               Double(touch.normalized.position.y)))
            }
        }
        MultitouchGestureRecognizer.shared.handleFrame(points: points)
        return 0
    }

    // MARK: - 捏合检测

    /// 处理一帧触点
    private func handleFrame(points: [(Double, Double)]) {
        queue.async { [weak self] in
            self?.processFrame(points: points)
        }
    }

    private func processFrame(points: [(Double, Double)]) {
        let activeCount = points.count

        // 手指抬起或不足目标数：结束当前手势追踪
        if activeCount < targetFingerCount {
            if trackingFingerCount >= targetFingerCount {
                evaluatePinch()
            }
            trackingFingerCount = 0
            startDistance = 0
            lastDistance = 0
            return
        }

        // 计算各指到质心的平均距离
        let (cx, cy) = centroid(points)
        var sumDist: Double = 0
        for (x, y) in points {
            sumDist += sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
        }
        let avgDist = sumDist / Double(points.count)

        if trackingFingerCount < targetFingerCount {
            // 开始新手势：记录起始距离
            startDistance = avgDist
            lastDistance = avgDist
            trackingFingerCount = activeCount
        } else {
            // 手势进行中：更新最新距离
            lastDistance = avgDist
        }
    }

    /// 手势结束时，根据起止距离判断捏合方向并触发回调
    private func evaluatePinch() {
        guard startDistance > 0.01 else { return }

        // 相对幅度：(last - start) / start
        // 负 = 捏拢(收缩), 正 = 张开(扩散)
        let magnitude = (lastDistance - startDistance) / startDistance

        let now = Date().timeIntervalSince1970
        if now - lastTriggerTime < cooldown {
            Logger.debug("Multitouch: 捏合幅度=\(String(format: "%.3f", magnitude)) 但在冷却期内，忽略")
            return
        }

        if magnitude <= -pinchThreshold {
            lastTriggerTime = now
            Logger.info("Multitouch: 检测到四指捏合 IN (幅度=\(String(format: "%.3f", magnitude)))")
            DispatchQueue.main.async { [weak self] in self?.callback(.pinchIn) }
        } else if magnitude >= pinchThreshold {
            lastTriggerTime = now
            Logger.info("Multitouch: 检测到四指张开 OUT (幅度=\(String(format: "%.3f", magnitude)))")
            DispatchQueue.main.async { [weak self] in self?.callback(.pinchOut) }
        } else {
            Logger.debug("Multitouch: 手势幅度不足 阈值=\(pinchThreshold) 实际=\(String(format: "%.3f", magnitude))")
        }
    }

    /// 计算质心
    private func centroid(_ points: [(Double, Double)]) -> (Double, Double) {
        guard !points.isEmpty else { return (0, 0) }
        var sx: Double = 0, sy: Double = 0
        for (x, y) in points { sx += x; sy += y }
        return (sx / Double(points.count), sy / Double(points.count))
    }
}
