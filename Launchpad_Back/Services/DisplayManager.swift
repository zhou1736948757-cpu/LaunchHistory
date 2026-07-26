import Foundation
import CoreGraphics

/// 显示管理器，用于控制屏幕刷新率
final class DisplayManager {

    // MARK: - Singleton

    static let shared = DisplayManager()

    private init() {
        log("DisplayManager initialized")
    }

    // MARK: - Public Methods

    /// 设置刷新率
    /// - Parameter mode: 刷新率模式
    func setRefreshRate(_ mode: RefreshRateMode) {
        log("Setting refresh rate to: \(mode)")

        switch mode {
        case .auto:
            setAutoRefreshRate()
        case .hz60:
            setRefreshRate(60.0)
        case .hz120:
            setRefreshRate(120.0)
        }
    }

    /// 获取支持的刷新率列表
    /// - Returns: 刷新率数组
    func getAvailableRefreshRates() -> [Double] {
        let displays = getActiveDisplays()
        var refreshRates: Set<Double> = []

        for displayID in displays {
            let modes = getDisplayModes(for: displayID)
            refreshRates.formUnion(modes)
        }

        let sortedRates = Array(refreshRates).sorted()
        log("Available refresh rates: \(sortedRates)")
        return sortedRates
    }

    /// 获取当前刷新率
    /// - Returns: 当前刷新率，如果获取失败返回 nil
    func getCurrentRefreshRate() -> Double? {
        let mainDisplay = CGMainDisplayID()
        var currentMode: CGDisplayMode?

        guard let modes = CGDisplayCopyAllDisplayModes(mainDisplay, nil) as? [CGDisplayMode] else {
            log("Failed to get display modes", level: .error)
            return nil
        }

        // 获取当前模式
        let currentDisplayMode = CGDisplayCopyDisplayMode(mainDisplay)

        if let currentMode = currentDisplayMode {
            let refreshRate = currentMode.refreshRate
            log("Current refresh rate: \(refreshRate)")
            return refreshRate
        }

        log("Failed to get current refresh rate", level: .error)
        return nil
    }

    // MARK: - Private Methods

    /// 设置特定刷新率
    /// - Parameter refreshRate: 目标刷新率
    private func setRefreshRate(_ refreshRate: Double) {
        let mainDisplay = CGMainDisplayID()

        guard let modes = CGDisplayCopyAllDisplayModes(mainDisplay, nil) as? [CGDisplayMode] else {
            log("Failed to get display modes for refresh rate \(refreshRate)", level: .error)
            return
        }

        // 查找匹配的显示模式
        var targetMode: CGDisplayMode?
        var bestMatch: CGDisplayMode?
        var smallestDifference = Double.greatestFiniteMagnitude

        // 获取当前显示信息
        let currentMode = CGDisplayCopyDisplayMode(mainDisplay)
        let currentWidth = currentMode?.width ?? 0
        let currentHeight = currentMode?.height ?? 0
        let currentRefreshRate = currentMode?.refreshRate ?? 0

        for mode in modes {
            // 检查分辨率是否匹配
            let modeWidth = mode.width
            let modeHeight = mode.height

            if modeWidth == currentWidth && modeHeight == currentHeight {
                let difference = abs(mode.refreshRate - refreshRate)
                if difference < smallestDifference {
                    smallestDifference = difference
                    bestMatch = mode
                }
            }
        }

        if let match = bestMatch {
            let error = CGDisplaySetDisplayMode(mainDisplay, match, nil)
            if error == .success {
                log("Successfully set refresh rate to \(match.refreshRate)Hz")
            } else {
                log("Failed to set refresh rate: \(error.rawValue)", level: .error)
            }
        } else {
            log("No matching display mode found for \(refreshRate)Hz", level: .error)
        }
    }

    /// 设置自动刷新率（允许 ProMotion）
    private func setAutoRefreshRate() {
        let mainDisplay = CGMainDisplayID()

        // 在 macOS 中，设置自动刷新率通常意味着使用默认的最高刷新率
        // 或者使用 IOKit 来启用 ProMotion
        guard let modes = CGDisplayCopyAllDisplayModes(mainDisplay, nil) as? [CGDisplayMode] else {
            log("Failed to get display modes for auto refresh rate", level: .error)
            return
        }

        // 获取当前显示信息
        let currentMode = CGDisplayCopyDisplayMode(mainDisplay)
        let currentWidth = currentMode?.width ?? 0
        let currentHeight = currentMode?.height ?? 0

        // 查找匹配的最高刷新率模式
        var highestMode: CGDisplayMode?
        var highestRefreshRate = 0.0

        for mode in modes {
            let modeWidth = mode.width
            let modeHeight = mode.height

            if modeWidth == currentWidth && modeHeight == currentHeight {
                if mode.refreshRate > highestRefreshRate {
                    highestRefreshRate = mode.refreshRate
                    highestMode = mode
                }
            }
        }

        if let mode = highestMode {
            let error = CGDisplaySetDisplayMode(mainDisplay, mode, nil)
            if error == .success {
                log("Successfully set auto refresh rate (maximum: \(mode.refreshRate)Hz)")
            } else {
                log("Failed to set auto refresh rate: \(error.rawValue)", level: .error)
            }
        }
    }

    /// 获取所有活跃的显示器
    /// - Returns: 显示器 ID 数组
    private func getActiveDisplays() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)

        let result = CGGetActiveDisplayList(16, &displays, &displayCount)

        if result == .success {
            return Array(displays.prefix(Int(displayCount)))
        } else {
            log("Failed to get active display list: \(result.rawValue)", level: .error)
            return []
        }
    }

    /// 获取指定显示器的显示模式
    /// - Parameter displayID: 显示器 ID
    /// - Returns: 刷新率集合
    private func getDisplayModes(for displayID: CGDirectDisplayID) -> Set<Double> {
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return []
        }

        var refreshRates = Set<Double>()
        for mode in modes {
            refreshRates.insert(mode.refreshRate)
        }

        return refreshRates
    }

    // MARK: - Logging

    private enum LogLevel {
        case info
        case error
    }

    private func log(_ message: String, level: LogLevel = .info) {
        let timestamp = DateFormatter()
        timestamp.dateFormat = "HH:mm:ss.SSS"
        let time = timestamp.string(from: Date())

        let prefix = level == .error ? "[ERROR]" : "[INFO]"
        print("\(prefix) DisplayManager [\(time)]: \(message)")
    }
}

// MARK: - RefreshRateMode

/// 刷新率模式
enum RefreshRateMode {
    case auto      // 自动（使用系统默认或 ProMotion）
    case hz60      // 60Hz
    case hz120     // 120Hz

    var description: String {
        switch self {
        case .auto:
            return "Auto"
        case .hz60:
            return "60Hz"
        case .hz120:
            return "120Hz"
        }
    }
}
