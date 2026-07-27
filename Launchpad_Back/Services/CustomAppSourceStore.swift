//
//  CustomAppSourceStore.swift
//  Launchpad_Back
//
//  Created on 2026-07-27.
//
//  負責使用者自訂 App 來源路徑的持久化（UserDefaults key "customAppPaths"，
//  內容為 [String]，每個元素為指向 .app 的絕對路徑）。
//

import Foundation

/// 使用者自訂 App 來源路徑的持久化存取層。
///
/// 用戶可在設定頁新增任意 `.app` 路徑，掃描時會與系統目錄合併，
/// 去重以 `stableIdentifier` 為準（bundleID 優先，否則用 path）。
final class CustomAppSourceStore {
    static let shared = CustomAppSourceStore()

    private let storageKey = "customAppPaths"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 取得所有自訂 App 路徑（已去重、順序保留）。
    func loadAll() -> [URL] {
        let raw = defaults.stringArray(forKey: storageKey) ?? []
        var seen = Set<String>()
        var result: [URL] = []
        for pathString in raw {
            let trimmed = pathString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(URL(fileURLWithPath: trimmed))
        }
        return result
    }

    /// 新增一個自訂 App 路徑（自動去重，已存在則為 no-op）。
    /// - Returns: 新增成功回傳 `true`；已存在或路徑為空回傳 `false`。
    @discardableResult
    func add(_ url: URL) -> Bool {
        let pathString = url.path
        guard !pathString.isEmpty else { return false }
        var existing = defaults.stringArray(forKey: storageKey) ?? []
        if existing.contains(pathString) { return false }
        existing.append(pathString)
        defaults.set(existing, forKey: storageKey)
        return true
    }

    /// 移除一個自訂 App 路徑。
    /// - Returns: 成功移除回傳 `true`；不存在回傳 `false`。
    @discardableResult
    func remove(_ url: URL) -> Bool {
        let pathString = url.path
        var existing = defaults.stringArray(forKey: storageKey) ?? []
        guard let index = existing.firstIndex(of: pathString) else { return false }
        existing.remove(at: index)
        defaults.set(existing, forKey: storageKey)
        return true
    }

    /// 是否包含指定路徑。
    func contains(_ url: URL) -> Bool {
        let pathString = url.path
        return (defaults.stringArray(forKey: storageKey) ?? []).contains(pathString)
    }

    /// 清除全部自訂來源。
    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
