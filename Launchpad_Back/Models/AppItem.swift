//
//  AppItem.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 2025/1/14.
//

import Foundation

/// Launchpad 項目類型協議
protocol LaunchpadItem: Identifiable, Hashable {
    var id: UUID { get }
    var name: String { get }
    var displayOrder: Int { get set }
}

/// 表示 macOS 應用程式的數據模型
struct AppItem: LaunchpadItem {
    let id: UUID
    /// 掃描自 Info.plist / 檔名的原始名稱，永不變動。
    let originalName: String
    /// 使用者自訂名稱。`nil` 或空字串表示使用 `originalName`。
    /// 由 `LaunchpadViewModel.renameApp` 寫入並觸發刷新，
    /// 此屬性不直接讀 UserDefaults，避免每幀 IO。
    var customName: String?
    let bundleID: String
    let path: String
    let isSystemApp: Bool
    var displayOrder: Int = 0
    var isHidden: Bool = false

    /// 對外展示名稱：自訂名稱優先，其次回退到原始名稱。
    /// 供 UI 顯示與排序使用。
    var displayName: String {
        if let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return originalName
    }

    /// 初始化應用程式項目
    /// - Parameters:
    ///   - id: 唯一識別碼（默認自動生成，用於持久化時可指定）
    ///   - name: 應用程式原始名稱（掃描自 Info.plist / 檔名）
    ///   - bundleID: Bundle 識別碼
    ///   - path: 應用程式路徑
    ///   - isSystemApp: 是否為系統應用
    ///   - displayOrder: 顯示順序
    ///   - isHidden: 是否隱藏
    ///   - customName: 使用者自訂名稱（可選）
    init(
        id: UUID = UUID(),
        name: String,
        bundleID: String,
        path: String,
        isSystemApp: Bool,
        displayOrder: Int = 0,
        isHidden: Bool = false,
        customName: String? = nil
    ) {
        self.id = id
        self.originalName = name
        self.customName = customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? customName
            : nil
        self.bundleID = bundleID
        self.path = path
        self.isSystemApp = isSystemApp
        self.displayOrder = displayOrder
        self.isHidden = isHidden
    }

    /// 為了相容 `LaunchpadItem` 協議與既有呼叫端，
    /// `name` 仍指向展示名稱（等同 `displayName`）。
    /// 內部需要原始名稱時請使用 `originalName`。
    var name: String { displayName }

    /// 用於持久化與去重的穩定識別鍵。
    /// 某些 App 沒有 bundle ID，此時退回使用安裝路徑。
    var stableIdentifier: String {
        bundleID.isEmpty ? path : bundleID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stableIdentifier)
    }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.stableIdentifier == rhs.stableIdentifier
    }
}

/// 表示應用程式文件夾的數據模型
struct AppFolder: LaunchpadItem {
    let id: UUID
    var name: String
    var apps: [AppItem]
    var displayOrder: Int = 0
    var isExpanded: Bool = false
    
    init(id: UUID = UUID(), name: String, apps: [AppItem], displayOrder: Int = 0) {
        self.id = id
        self.name = name
        self.apps = apps
        self.displayOrder = displayOrder
    }
    
    /// 文件夾中應用數量
    var appCount: Int {
        apps.count
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AppFolder, rhs: AppFolder) -> Bool {
        lhs.id == rhs.id
    }
}

/// Launchpad 中可顯示的項目（可以是應用或文件夾）
enum LaunchpadDisplayItem: Identifiable, Hashable {
    case app(AppItem)
    case folder(AppFolder)
    
    var id: UUID {
        switch self {
        case .app(let app): return app.id
        case .folder(let folder): return folder.id
        }
    }
    
    var name: String {
        switch self {
        case .app(let app): return app.name
        case .folder(let folder): return folder.name
        }
    }
    
    var displayOrder: Int {
        get {
            switch self {
            case .app(let app): return app.displayOrder
            case .folder(let folder): return folder.displayOrder
            }
        }
        set {
            switch self {
            case .app(var app):
                app.displayOrder = newValue
                self = .app(app)
            case .folder(var folder):
                folder.displayOrder = newValue
                self = .folder(folder)
            }
        }
    }

    var persistenceKey: String {
        switch self {
        case .app(let app):
            return "app:\(app.stableIdentifier)"
        case .folder(let folder):
            return "folder:\(folder.id.uuidString)"
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
