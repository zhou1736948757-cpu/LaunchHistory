//
//  UserPreferences.swift
//  Launchpad_Back
//
//  Created on 2026-07-25.
//

import Foundation
import SwiftUI
import Combine

/// 窗口模式枚举
enum WindowMode: String, Codable, CaseIterable {
    case fullscreen = "fullscreen"
    case windowed = "windowed"
    case centered = "centered"

    var localizedName: LocalizedStringKey {
        switch self {
        case .fullscreen: return "mode_fullscreen"
        case .windowed: return "mode_windowed"
        case .centered: return "mode_centered"
        }
    }
}

/// 刷新率枚举
enum RefreshRate: String, Codable, CaseIterable {
    case low = "30"
    case medium = "60"
    case high = "120"
    case ultra = "144"

    var value: Int {
        switch self {
        case .low: return 30
        case .medium: return 60
        case .high: return 120
        case .ultra: return 144
        }
    }

    var localizedName: LocalizedStringKey {
        switch self {
        case .low: return "refresh_30_fps"
        case .medium: return "refresh_60_fps"
        case .high: return "refresh_120_fps"
        case .ultra: return "refresh_144_fps"
        }
    }
}

/// 滚动模式枚举
enum ScrollMode: String, Codable, CaseIterable {
    case smooth = "smooth"
    case discrete = "discrete"
    case momentum = "momentum"

    var localizedName: LocalizedStringKey {
        switch self {
        case .smooth: return "scroll_smooth"
        case .discrete: return "scroll_discrete"
        case .momentum: return "scroll_momentum"
        }
    }
}

/// 启动方式枚举
enum LaunchMethod: String, Codable, CaseIterable {
    case singleClick = "single_click"
    case doubleClick = "double_click"
    case enterKey = "enter_key"

    var localizedName: LocalizedStringKey {
        switch self {
        case .singleClick: return "launch_single_click"
        case .doubleClick: return "launch_double_click"
        case .enterKey: return "launch_enter_key"
        }
    }
}

/// 手势类型枚举
enum GestureType: String, Codable, CaseIterable {
    case none = "none"
    case swipeUp = "swipe_up"
    case swipeDown = "swipe_down"
    case swipeLeft = "swipe_left"
    case swipeRight = "swipe_right"
    case pinchIn = "pinch_in"
    case pinchOut = "pinch_out"

    var localizedName: LocalizedStringKey {
        switch self {
        case .none: return "gesture_none"
        case .swipeUp: return "gesture_swipe_up"
        case .swipeDown: return "gesture_swipe_down"
        case .swipeLeft: return "gesture_swipe_left"
        case .swipeRight: return "gesture_swipe_right"
        case .pinchIn: return "gesture_pinch_in"
        case .pinchOut: return "gesture_pinch_out"
        }
    }
}

/// 图标尺寸枚举
enum IconSize: String, Codable, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extra_large"

    var size: CGFloat {
        switch self {
        case .small: return 48
        case .medium: return 64
        case .large: return 80
        case .extraLarge: return 96
        }
    }

    var localizedName: LocalizedStringKey {
        switch self {
        case .small: return "size_small"
        case .medium: return "size_medium"
        case .large: return "size_large"
        case .extraLarge: return "size_extra_large"
        }
    }
}

/// 快捷键组合结构体
struct KeyCombo: Codable, Equatable, Hashable {
    var key: String
    var modifiers: [String]

    init(key: String, modifiers: [String] = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// 格式化快捷键显示文本
    var displayString: String {
        let modifierSymbols = modifiers.map { modifier in
            switch modifier.lowercased() {
            case "command": return "⌘"
            case "control": return "⌃"
            case "option", "alt": return "⌥"
            case "shift": return "⇧"
            case "function", "fn": return "fn"
            default: return modifier
            }
        }
        return modifierSymbols.joined() + key.uppercased()
    }

    /// 常用快捷键预设
    static let commandSpace = KeyCombo(key: "Space", modifiers: ["command"])
    static let optionSpace = KeyCombo(key: "Space", modifiers: ["option"])
    static let controlSpace = KeyCombo(key: "Space", modifiers: ["control"])
    static let fnSpace = KeyCombo(key: "Space", modifiers: ["fn"])
    static let doubleTapControl = KeyCombo(key: "⎋", modifiers: []) // Escape 键
}

/// 用户偏好设置主结构体
struct UserPreferences: Codable {
    // MARK: - 窗口设置
    var windowMode: WindowMode
    var windowOpacity: Double
    var blurEffectEnabled: Bool
    var blurIntensity: Double
    var animationEnabled: Bool
    var animationDuration: Double

    // MARK: - 显示设置
    var iconSize: IconSize
    var showIconLabels: Bool
    var showHiddenApps: Bool
    var showRecentApps: Bool
    var recentAppsCount: Int
    var gridSize: Int // 每行图标数量

    // MARK: - 性能设置
    var refreshRate: RefreshRate
    var hardwareAccelerationEnabled: Bool
    var memoryOptimizationEnabled: Bool

    // MARK: - 交互设置
    var scrollMode: ScrollMode
    var launchMethod: LaunchMethod
    var doubleTapEnabled: Bool
    var doubleTapSensitivity: Double
    var scrollSpeed: Double

    // MARK: - 手势设置
    var openGesture: GestureType
    var closeGesture: GestureType
    var searchGesture: GestureType
    var gesturesEnabled: Bool

    // MARK: - 搜索设置
    var searchEnabled: Bool
    var searchOnLaunch: Bool
    var searchIncludeHiddenApps: Bool
    var searchHistoryEnabled: Bool
    var searchHistoryLimit: Int

    // MARK: - 声音设置
    var soundEnabled: Bool
    var launchSoundEnabled: Bool
    var hoverSoundEnabled: Bool
    var volume: Double

    // MARK: - 快捷键设置
    var toggleHotKey: HotKeyCombo
    var searchHotKey: HotKeyCombo
    var quitAppHotKey: HotKeyCombo

    // MARK: - 高级设置
    var autoLaunchAtLogin: Bool
    var checkForUpdates: Bool
    var sendAnonymousData: Bool

    /// 默认配置
    static let `default` = UserPreferences(
        // 窗口设置
        windowMode: WindowMode.fullscreen,
        windowOpacity: 0.95,
        blurEffectEnabled: true,
        blurIntensity: 0.8,
        animationEnabled: true,
        animationDuration: 0.25,

        // 显示设置
        iconSize: IconSize.medium,
        showIconLabels: true,
        showHiddenApps: false,
        showRecentApps: true,
        recentAppsCount: 6,
        gridSize: 6,

        // 性能设置
        refreshRate: RefreshRate.medium,
        hardwareAccelerationEnabled: true,
        memoryOptimizationEnabled: true,

        // 交互设置
        scrollMode: ScrollMode.smooth,
        launchMethod: LaunchMethod.singleClick,
        doubleTapEnabled: true,
        doubleTapSensitivity: 0.5,
        scrollSpeed: 1.0,

        // 手势设置
        openGesture: GestureType.swipeUp,
        closeGesture: GestureType.swipeDown,
        searchGesture: GestureType.pinchIn,
        gesturesEnabled: true,

        // 搜索设置
        searchEnabled: true,
        searchOnLaunch: false,
        searchIncludeHiddenApps: false,
        searchHistoryEnabled: true,
        searchHistoryLimit: 10,

        // 声音设置
        soundEnabled: true,
        launchSoundEnabled: true,
        hoverSoundEnabled: false,
        volume: 0.5,

        // 快捷键设置
        toggleHotKey: HotKeyCombo(keyCode: 0x31, modifiers: 0x100000), // Cmd + Space
        searchHotKey: HotKeyCombo(keyCode: 0x31, modifiers: 0x080000), // Option + Space
        quitAppHotKey: HotKeyCombo(keyCode: 0x0C, modifiers: 0x100000), // Cmd + Q

        // 高级设置
        autoLaunchAtLogin: false,
        checkForUpdates: true,
        sendAnonymousData: false
    )
}

/// 用户偏好设置管理器（单例模式）
final class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()

    @Published private(set) var preferences: UserPreferences

    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "userPreferences"

    private init() {
        // 从 UserDefaults 加载保存的偏好设置，如果没有则使用默认值
        if let data = userDefaults.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = UserPreferences.default
        }
    }

    /// 保存偏好设置到 UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            userDefaults.set(encoded, forKey: preferencesKey)
        }
    }

    /// 更新偏好设置
    func update(_ newPreferences: UserPreferences) {
        preferences = newPreferences
        save()
    }

    /// 更新单个偏好设置项
    func update<T>(keyPath: WritableKeyPath<UserPreferences, T>, value: T) {
        preferences[keyPath: keyPath] = value
        save()
    }

    /// 重置为默认设置
    func resetToDefaults() {
        preferences = UserPreferences.default
        save()
    }

    /// 导出设置为 JSON
    func exportSettings() -> String? {
        if let encoded = try? JSONEncoder().encode(preferences),
           let jsonString = String(data: encoded, encoding: .utf8) {
            return jsonString
        }
        return nil
    }

    /// 从 JSON 导入设置
    func importSettings(jsonString: String) -> Bool {
        if let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            preferences = decoded
            save()
            return true
        }
        return false
    }

    /// 清除所有设置（恢复出厂设置）
    func clearAllSettings() {
        userDefaults.removeObject(forKey: preferencesKey)
        preferences = UserPreferences.default
    }
}

// MARK: - 便捷扩展
extension UserPreferencesManager {
    /// 窗口模式快捷访问
    var windowMode: WindowMode {
        get { preferences.windowMode }
        set { update(keyPath: \.windowMode, value: newValue) }
    }

    /// 图标尺寸快捷访问
    var iconSize: IconSize {
        get { preferences.iconSize }
        set { update(keyPath: \.iconSize, value: newValue) }
    }

    /// 刷新率快捷访问
    var refreshRate: RefreshRate {
        get { preferences.refreshRate }
        set { update(keyPath: \.refreshRate, value: newValue) }
    }

    /// 动画启用状态快捷访问
    var animationEnabled: Bool {
        get { preferences.animationEnabled }
        set { update(keyPath: \.animationEnabled, value: newValue) }
    }

    /// 模糊效果启用状态快捷访问
    var blurEffectEnabled: Bool {
        get { preferences.blurEffectEnabled }
        set { update(keyPath: \.blurEffectEnabled, value: newValue) }
    }
}