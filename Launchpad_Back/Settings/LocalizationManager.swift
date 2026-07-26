//
//  LocalizationManager.swift
//  Launchpad_Back
//
//  Created on 2026-07-27.
//

import Foundation
import Combine

/// 语言偏好选项
///
/// 持久化于 UserDefaults key "languagePreference"。
/// - `system`：跟随系统语言（按 `Locale`/`Bundle` 推断）
/// - 其余：手动指定，写入 `AppleLanguages` 后需重启 app 生效
enum LanguagePreference: String, CaseIterable {
    case system = "system"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en     = "en"

    /// 设置面板显示名称（本地化）
    var displayName: String {
        switch self {
        case .system: return String(localized: "lang_system")
        case .zhHans: return String(localized: "lang_zh_hans")
        case .zhHant: return String(localized: "lang_zh_hant")
        case .en:     return String(localized: "lang_en")
        }
    }
}

/// 本地化管理器（单例）
///
/// 职责：
/// 1. 读取系统语言并归一化为支持的语言代码（`zh-Hans` / `zh-Hant` / `en`）
/// 2. 维护用户手动选择的语言偏好（UserDefaults key `languagePreference`）
/// 3. 当用户手动选择语言时，写入 `AppleLanguages` 到 UserDefaults，
///    macOS App 在下次启动时据此切换 Bundle 语言；选“跟随系统”时移除自定义。
///
/// 注意：macOS 下 SwiftUI 的 `LocalizedStringKey` / `String(localized:)` 解析依赖
/// Bundle 的语言，而 Bundle 语言在进程启动时确定。因此手动切换语言需重启 app 才能对
/// `LocalizedStringKey` 生效。`currentLanguageCode` 供 UI 层手动取串时即时使用。
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// UserDefaults keys
    static let preferenceKey     = "languagePreference"
    static let appleLanguagesKey = "AppleLanguages"

    /// 当前应使用的语言代码（供 UI 手动取串）。变化时通知观察者。
    @Published private(set) var currentLanguageCode: String

    private init() {
        self.currentLanguageCode = LocalizationManager.computeCurrentLanguageCode()

        // 运行时验证 String Catalog 可用性（Release 也输出），便于诊断。
        Logger.debug("⦿ Localization ready, currentLanguageCode=\(currentLanguageCode), catalogTest=\(String(localized: "search"))")
    }

    // MARK: - 偏好读取

    /// 用户语言偏好（从 UserDefaults 读取）
    var preference: LanguagePreference {
        let raw = UserDefaults.standard.string(forKey: Self.preferenceKey) ?? LanguagePreference.system.rawValue
        return LanguagePreference(rawValue: raw) ?? .system
    }

    /// 推断系统真实语言代码（不受 AppleLanguages 自定义污染）
    ///
    /// 规则：
    /// - 优先取 `Locale.preferredLanguages`（系统真实偏好，反映用户在系统设置里选的语言）
    ///   不用 `Bundle.main.preferredLocalizations`，因为后者会把自定义的 `AppleLanguages`
    ///   计入——切回“跟随系统”但未重启时，会错误返回旧的手动语言。
    /// - `zh-Hant`/`zh-tw` 开头 → `zh-Hant`
    /// - `zh-hans`/`zh-cn`/`zh` 开头 → `zh-Hans`
    /// - `en` 开头 → `en`
    /// - 其他 → `en`（默认）
    static var systemLanguageCode: String {
        for lang in Locale.preferredLanguages {
            if let resolved = resolveCode(from: lang) {
                return resolved
            }
        }
        // 兜底：Bundle.main.preferredLocalizations
        if let first = Bundle.main.preferredLocalizations.first,
           let resolved = resolveCode(from: first) {
            return resolved
        }
        return LanguagePreference.en.rawValue
    }

    // MARK: - 偏好应用

    /// 应用新的语言偏好：持久化偏好 + 同步 `AppleLanguages` + 刷新 `currentLanguageCode`
    ///
    /// - `system`：移除自定义 `AppleLanguages`，恢复跟随系统
    /// - 手动语言：写入 `AppleLanguages = [lang]`，需重启 app 生效
    func applyPreference(_ pref: LanguagePreference) {
        UserDefaults.standard.set(pref.rawValue, forKey: Self.preferenceKey)

        switch pref {
        case .system:
            UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
            Logger.info("⦿ Localization: follow system, cleared AppleLanguages")
        case .zhHans, .zhHant, .en:
            UserDefaults.standard.set([pref.rawValue], forKey: Self.appleLanguagesKey)
            Logger.info("⦿ Localization: set AppleLanguages=[\(pref.rawValue)], restart required to take effect")
        }

        currentLanguageCode = LocalizationManager.computeCurrentLanguageCode()
    }

    /// 是否需要重启以使语言切换对 `LocalizedStringKey` 生效
    ///
    /// 判断依据：用户「想要的目标语言」与「Bundle 当前实际加载的语言」是否一致。
    /// 不一致就需要重启（因为 Bundle 语言在进程启动时确定，运行时改 AppleLanguages 不会立即生效）。
    /// 这覆盖了「手动选了某语言后又切回跟随系统」的场景——切回系统但未重启时，
    /// Bundle 仍是旧语言，应继续提示重启，而非静默不提示。
    var needsRestart: Bool {
        let targetCode: String
        switch preference {
        case .system: targetCode = Self.systemLanguageCode
        case .zhHans, .zhHant, .en: targetCode = preference.rawValue
        }
        // Bundle.main.preferredLocalizations 反映进程启动时确定的语言
        let loadedCode = Bundle.main.preferredLocalizations.first
            .flatMap { Self.resolveCode(from: $0) }
            ?? LanguagePreference.en.rawValue
        return targetCode != loadedCode
    }

    // MARK: - 私有工具

    /// 计算当前应使用的语言代码
    private static func computeCurrentLanguageCode() -> String {
        let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? LanguagePreference.system.rawValue
        let pref = LanguagePreference(rawValue: raw) ?? .system
        switch pref {
        case .system: return systemLanguageCode
        default:      return pref.rawValue
        }
    }

    /// 将任意语言标识（如 `zh-Hans-CN`、`zh-Hant_TW`、`en-US`）归一化为支持的语言代码
    private static func resolveCode(from identifier: String) -> String? {
        let lower = identifier.lowercased()
        if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") {
            return LanguagePreference.zhHant.rawValue
        }
        if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") || lower.hasPrefix("zh") {
            return LanguagePreference.zhHans.rawValue
        }
        if lower.hasPrefix("en") {
            return LanguagePreference.en.rawValue
        }
        return nil
    }
}
