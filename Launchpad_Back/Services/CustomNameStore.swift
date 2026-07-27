//
//  CustomNameStore.swift
//  Launchpad_Back
//
//  Created on 2026-07-27.
//
//  負責 App 自訂名稱的持久化（UserDefaults key "customNames"，
//  內容為 [stableIdentifier: 自訂名稱]）。
//

import Foundation

/// App 自訂名稱的持久化存取層。
///
/// 為了避免 `displayName` 在每次 UI 刷新時讀取 UserDefaults，
/// 本類別只負責「讀/寫字典」，由 `LaunchpadViewModel` 在
/// 載入與重命名時把值同步到對應 `AppItem.customName`。
final class CustomNameStore {
    static let shared = CustomNameStore()

    private let storageKey = "customNames"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 取得所有已保存的自訂名稱（stableIdentifier -> 自訂名稱）。
    /// 自動剔除空白字串值。
    func loadAll() -> [String: String] {
        guard let raw = defaults.dictionary(forKey: storageKey) as? [String: String] else {
            return [:]
        }
        var cleaned: [String: String] = [:]
        for (key, value) in raw {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                cleaned[key] = trimmed
            }
        }
        return cleaned
    }

    /// 覆寫整份自訂名稱表。
    func saveAll(_ entries: [String: String]) {
        var cleaned: [String: String] = [:]
        for (key, value) in entries {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                cleaned[key] = trimmed
            }
        }
        defaults.set(cleaned, forKey: storageKey)
    }

    /// 設定單一 App 的自訂名稱。
    /// 傳入 `nil` 或空白字串即移除該鍵（恢復原名）。
    func setCustomName(_ newName: String?, for stableIdentifier: String) {
        var entries = loadAll()
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            entries.removeValue(forKey: stableIdentifier)
        } else {
            entries[stableIdentifier] = trimmed
        }
        defaults.set(entries, forKey: storageKey)
    }

    /// 讀取單一 App 的自訂名稱，未設定時回傳 `nil`。
    func customName(for stableIdentifier: String) -> String? {
        guard let value = loadAll()[stableIdentifier] else { return nil }
        return value
    }

    /// 移除單一 App 的自訂名稱。
    func removeCustomName(for stableIdentifier: String) {
        var entries = loadAll()
        entries.removeValue(forKey: stableIdentifier)
        defaults.set(entries, forKey: storageKey)
    }
}
