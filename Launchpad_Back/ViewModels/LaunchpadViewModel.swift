//
//  LaunchpadViewModel.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 2025/1/14.
//  Optimized for memory usage on 2025/1/16
//

import SwiftUI
import Combine

private struct SearchIndexEntry {
    let stableIdentifier: String
    let searchText: String
}

/// 主要的 Launchpad ViewModel
/// 負責應用程式列表的管理和狀態
///
/// 記憶體優化：
/// - 使用防抖動機制減少頻繁的 UserDefaults 寫入
/// - 優化 @Published 屬性使用
/// - 改善記憶體釋放邏輯
final class LaunchpadViewModel: ObservableObject {
    private let hiddenAppsKey = "hiddenApps"
    private var hiddenAppsStorage: [String] {
        get {
            defaults.stringArray(forKey: hiddenAppsKey) ?? []
        }
        set {
            defaults.set(newValue, forKey: hiddenAppsKey)
        }
    }

    var hiddenApps: [String] {
        get { hiddenAppsStorage }
        set { hiddenAppsStorage = newValue }
    }

    /// 全部已掃描應用（含隱藏），保留原始資料供隱藏管理頁與重命名反查使用。
    @Published private(set) var allApps: [AppItem] = []

    /// 目前可見（未隱藏）的應用。等價於 `allApps.filter { !isAppHidden($0) }`。
    /// 保留此屬性以相容既有呼叫端（`viewModel.apps`）。
    @Published var apps: [AppItem] = []
    @Published var folders: [AppFolder] = []
    @Published var displayItems: [LaunchpadDisplayItem] = [] {
        didSet {
            // 使用防抖動，避免頻繁保存
            scheduleSave()
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var searchableApps: [AppItem] = []

    private let scannerService: AppScannerService
    private let launcherService: AppLauncherService
    private let defaults: UserDefaults
    private let customNameStore: CustomNameStore
    private let customAppSourceStore: CustomAppSourceStore
    private var searchIndex: [SearchIndexEntry] = []
    private var appsByStableIdentifier: [String: AppItem] = [:]
    private var appsByBundleIdentifier: [String: AppItem] = [:]
    private var searchRevision = 0
    private var cachedFilteredAppsQuery: String?
    private var cachedFilteredAppsRevision = -1
    private var cachedFilteredAppsResult: [AppItem] = []
    private var cachedFilteredDisplayItemsQuery: String?
    private var cachedFilteredDisplayItemsRevision = -1
    private var cachedFilteredDisplayItemsResult: [LaunchpadDisplayItem] = []

    // 持久化存儲鍵
    private let orderKey = "launchpad_item_order"
    private let foldersKey = "launchpad_folders"

    // 優化：防抖動計時器，減少頻繁的 UserDefaults 寫入
    private var saveOrderWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.5

    init(
        scannerService: AppScannerService = AppScannerService(),
        launcherService: AppLauncherService = AppLauncherService(),
        defaults: UserDefaults = .standard,
        customNameStore: CustomNameStore = .shared,
        customAppSourceStore: CustomAppSourceStore = .shared
    ) {
        self.scannerService = scannerService
        self.launcherService = launcherService
        self.defaults = defaults
        self.customNameStore = customNameStore
        self.customAppSourceStore = customAppSourceStore
        Logger.info("LaunchpadViewModel initialized with memory optimizations")
    }
    
    deinit {
        // 確保保存待處理的更改
        saveOrderWorkItem?.cancel()
        saveOrderImmediately()
        Logger.debug("LaunchpadViewModel deinitialized")
    }
    
    /// 加載已安裝的應用程式
    func loadInstalledApps() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        Logger.info("Starting app loading...")

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            // 合併使用者自訂來源路徑
            let customPaths = self.customAppSourceStore.loadAll()
            let scannedApps = self.scannerService.scanInstalledApps(customAppPaths: customPaths)
            // 套用持久化的自訂名稱（stableIdentifier -> customName）
            let customNames = self.customNameStore.loadAll()
            let allApps = scannedApps.map { app -> AppItem in
                var copy = app
                copy.customName = customNames[app.stableIdentifier]
                return copy
            }
            let apps = allApps.filter { !self.isAppHidden($0) }
            let searchState = self.buildSearchState(from: apps)

            DispatchQueue.main.async {
                self.allApps = allApps
                self.apps = apps
                self.searchableApps = searchState.apps
                self.appsByStableIdentifier = searchState.appsByStableIdentifier
                self.appsByBundleIdentifier = searchState.appsByBundleIdentifier
                self.searchIndex = searchState.index
                self.invalidateSearchCaches()
                self.initializeDisplayItems()
                self.isLoading = false
                Logger.info("App loading completed. Found \(apps.count) applications (total incl. hidden: \(allApps.count))")
            }
        }
    }
    
    /// 根據最新的 apps / folders 重新同步顯示列表，保留現有排序。
    private func reconcileDisplayItems() {
        let appsInFolders = Set(folders.flatMap { $0.apps.map(\.stableIdentifier) })
        var standaloneAppsByIdentifier = Dictionary(
            uniqueKeysWithValues: apps
                .filter { !appsInFolders.contains($0.stableIdentifier) }
                .map { ($0.stableIdentifier, $0) }
        )
        var foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var reconciledItems: [LaunchpadDisplayItem] = []

        for item in displayItems {
            switch item {
            case .app(let app):
                let key = app.stableIdentifier
                guard let latestApp = standaloneAppsByIdentifier.removeValue(forKey: key),
                      !isAppHidden(latestApp) else {
                    continue
                }
                reconciledItems.append(.app(latestApp))
            case .folder(let folder):
                let filteredFolderApps = folder.apps.filter { !isAppHidden($0) }
                guard let latestFolder = foldersById.removeValue(forKey: folder.id),
                      !filteredFolderApps.isEmpty else {
                    continue
                }
                let updatedFolder = AppFolder(id: folder.id, name: folder.name, apps: filteredFolderApps)
                reconciledItems.append(.folder(updatedFolder))
            }
        }

        let remainingApps = standaloneAppsByIdentifier.values
            .filter { !isAppHidden($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(LaunchpadDisplayItem.app)
        let remainingFolders = foldersById.values
            .map { folder in
                let filteredApps = folder.apps.filter { !isAppHidden($0) }
                return AppFolder(id: folder.id, name: folder.name, apps: filteredApps)
            }
            .filter { !$0.apps.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(LaunchpadDisplayItem.folder)

        displayItems = reconciledItems + remainingApps + remainingFolders
    }
    
    /// 初始化顯示項目列表（首次載入時按名稱排序，或從保存的順序載入）
    private func initializeDisplayItems() {
        // 嘗試載入保存的文件夾
        loadFolders()

        // 獲取所有在文件夾中的應用 ID
        let appsInFolders = Set(folders.flatMap { $0.apps.map(\.stableIdentifier) })
        let standaloneAppsByIdentifier = Dictionary(
            uniqueKeysWithValues: apps
                .filter { !appsInFolders.contains($0.stableIdentifier) }
                .map { ($0.stableIdentifier, $0) }
        )
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id.uuidString, $0) })

        // 嘗試載入保存的順序
        if let savedOrder = loadOrder() {
            var orderedItems: [LaunchpadDisplayItem] = []
            var remainingApps = standaloneAppsByIdentifier
            var remainingFolders = foldersById

            // 按保存的順序排列
            for itemKey in savedOrder {
                // 檢查是否為文件夾 (格式: "folder:UUID")
                if itemKey.hasPrefix("folder:") {
                    let folderId = String(itemKey.dropFirst(7))
                    if let folder = remainingFolders.removeValue(forKey: folderId) {
                        let filteredFolderApps = folder.apps.filter { !isAppHidden($0) }
                        if !filteredFolderApps.isEmpty {
                            let updatedFolder = AppFolder(id: folder.id, name: folder.name, apps: filteredFolderApps)
                            orderedItems.append(.folder(updatedFolder))
                        }
                    }
                }
                // 檢查是否為應用 (格式: "app:stableIdentifier")
                else if itemKey.hasPrefix("app:") {
                    let appIdentifier = String(itemKey.dropFirst(4))
                    if let app = remainingApps.removeValue(forKey: appIdentifier), !isAppHidden(app) {
                        orderedItems.append(.app(app))
                    }
                }
            }

            // 添加新安裝的應用（不在保存順序中的）
            let newApps = remainingApps.values
                .filter { !isAppHidden($0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(LaunchpadDisplayItem.app)
            let newFolders = remainingFolders.values
                .map { folder in
                    let filteredApps = folder.apps.filter { !isAppHidden($0) }
                    return AppFolder(id: folder.id, name: folder.name, apps: filteredApps)
                }
                .filter { !$0.apps.isEmpty }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(LaunchpadDisplayItem.folder)
            orderedItems.append(contentsOf: newApps)
            orderedItems.append(contentsOf: newFolders)

            displayItems = orderedItems
            Logger.info("Loaded saved order with \(orderedItems.count) items")
        } else {
            // 沒有保存的順序，按名稱排序
            var items: [LaunchpadDisplayItem] = []

            // 添加不在文件夾中的應用
            let standaloneApps = apps.filter { !appsInFolders.contains($0.stableIdentifier) && !isAppHidden($0) }
            items.append(contentsOf: standaloneApps.map { .app($0) })

            // 添加文件夾（過濾掉為空的文件夾）
            items.append(contentsOf: folders.compactMap { folder in
                let filteredApps = folder.apps.filter { !isAppHidden($0) }
                return filteredApps.isEmpty ? nil : .folder(AppFolder(id: folder.id, name: folder.name, apps: filteredApps))
            })

            // 按名稱排序
            displayItems = items.sorted { item1, item2 in
                item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
            Logger.info("No saved order, sorted by name")
        }
    }

    private func defaultSortedDisplayItems() -> [LaunchpadDisplayItem] {
        apps
            .filter { !isAppHidden($0) }
            .map(LaunchpadDisplayItem.app)
            .sorted { item1, item2 in
                item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
    }
    
    // MARK: - 持久化（優化版）
    
    /// 排程保存（使用防抖動）
    private func scheduleSave() {
        saveOrderWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveOrderImmediately()
        }
        
        saveOrderWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }
    
    /// 立即保存當前順序（內部方法）
    private func saveOrderImmediately() {
        let order = displayItems.map(\.persistenceKey)
        
        // 優化：批次寫入，減少 I/O 操作
        defaults.set(order, forKey: orderKey)
        saveFolders(to: defaults)
        
        Logger.debug("Saved order with \(order.count) items and \(folders.count) folders")
    }
    
    /// 保存當前順序（公開方法，用於需要立即保存的場景）
    func saveOrder() {
        saveOrderImmediately()
    }
    
    /// 載入保存的順序
    private func loadOrder() -> [String]? {
        defaults.stringArray(forKey: orderKey)
    }
    
    /// 保存文件夾（優化：接受 UserDefaults 參數，避免重複獲取）
    private func saveFolders(to defaults: UserDefaults? = nil) {
        let defaults = defaults ?? self.defaults
        let folderData = folders.map { folder -> [String: Any] in
            [
                "id": folder.id.uuidString,
                "name": folder.name,
                "appIdentifiers": folder.apps.map(\.stableIdentifier)
            ]
        }
        defaults.set(folderData, forKey: foldersKey)
    }
    
    /// 載入文件夾
    private func loadFolders() {
        guard let folderData = defaults.array(forKey: foldersKey) as? [[String: Any]] else {
            return
        }
        
        folders = folderData.compactMap { data -> AppFolder? in
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = data["name"] as? String else {
                return nil
            }
            
            // 支援舊格式 (appIds / appBundleIds) 和新格式 (appIdentifiers)
            let folderApps: [AppItem]
            if let identifiers = data["appIdentifiers"] as? [String] {
                folderApps = identifiers.compactMap(app(withIdentifier:))
            } else if let bundleIds = data["appBundleIds"] as? [String] {
                folderApps = bundleIds.compactMap(app(withBundleIdentifier:))
            } else if let appIds = data["appIds"] as? [String] {
                folderApps = appIds.compactMap { appIdString -> AppItem? in
                    guard let appId = UUID(uuidString: appIdString) else { return nil }
                    return apps.first { $0.id == appId }
                }
            } else {
                return nil
            }
            
            guard !folderApps.isEmpty else { return nil }
            
            return AppFolder(id: id, name: name, apps: folderApps)
        }
        
        Logger.info("Loaded \(folders.count) folders")
    }
    
    // MARK: - 圖標預載入
    
    /// 根據目前頁面預載入相鄰頁的圖標，降低翻頁時的載入延遲。
    func updateActivePage(_ page: Int, itemsPerPage: Int) {
        preloadAdjacentPageIcons(page, itemsPerPage: max(1, itemsPerPage))
    }
    
    /// 預載入相鄰頁面的圖標
    private func preloadAdjacentPageIcons(_ page: Int, itemsPerPage: Int) {
        guard !displayItems.isEmpty else { return }
        
        let startIndex = max(0, (page - 1) * itemsPerPage)
        let endIndex = min(displayItems.count, (page + 2) * itemsPerPage)
        guard startIndex < endIndex else { return }
        
        let requests = displayItems[startIndex..<endIndex].compactMap { item -> (path: String, appName: String?)? in
            if case .app(let app) = item {
                return (path: app.path, appName: app.name)
            }
            return nil
        }
        
        AppIconCache.shared.preloadIcons(for: requests)
    }

    private func buildSearchState(from apps: [AppItem]) -> (
        apps: [AppItem],
        index: [SearchIndexEntry],
        appsByStableIdentifier: [String: AppItem],
        appsByBundleIdentifier: [String: AppItem]
    ) {
        let searchableApps = Dictionary(grouping: apps, by: \.stableIdentifier)
            .compactMapValues(\.first)
            .values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let appsByStableIdentifier = Dictionary(uniqueKeysWithValues: searchableApps.map { ($0.stableIdentifier, $0) })
        let appsByBundleIdentifier = Dictionary(grouping: searchableApps.filter { !$0.bundleID.isEmpty }, by: \.bundleID)
            .compactMapValues(\.first)

        let index = searchableApps.map { app in
            // 搜尋索引同時包含原始名稱與展示名稱，讓使用者兩者皆可搜尋
            SearchIndexEntry(
                stableIdentifier: app.stableIdentifier,
                searchText: "\(app.originalName)\n\(app.displayName)\n\(app.bundleID)\n\(app.path)".lowercased()
            )
        }

        return (searchableApps, index, appsByStableIdentifier, appsByBundleIdentifier)
    }
    
    private func app(withIdentifier identifier: String) -> AppItem? {
        appsByStableIdentifier[identifier]
    }

    private func app(withBundleIdentifier bundleIdentifier: String) -> AppItem? {
        appsByBundleIdentifier[bundleIdentifier]
    }

    private func invalidateSearchCaches() {
        searchRevision &+= 1
        cachedFilteredAppsQuery = nil
        cachedFilteredAppsRevision = -1
        cachedFilteredAppsResult = []
        cachedFilteredDisplayItemsQuery = nil
        cachedFilteredDisplayItemsRevision = -1
        cachedFilteredDisplayItemsResult = []
    }
    
    func filteredApps(matching searchText: String) -> [AppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return searchableApps
        }

        if cachedFilteredAppsQuery == query, cachedFilteredAppsRevision == searchRevision {
            return cachedFilteredAppsResult
        }
        
        let result = searchIndex
            .filter { $0.searchText.contains(query) }
            .compactMap { appsByStableIdentifier[$0.stableIdentifier] }
        cachedFilteredAppsQuery = query
        cachedFilteredAppsRevision = searchRevision
        cachedFilteredAppsResult = result
        return result
    }
    
    func filteredDisplayItems(matching searchText: String) -> [LaunchpadDisplayItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return displayItems
        }

        if cachedFilteredDisplayItemsQuery == query, cachedFilteredDisplayItemsRevision == searchRevision {
            return cachedFilteredDisplayItemsResult
        }
        
        let result = filteredApps(matching: query).map(LaunchpadDisplayItem.app)
        cachedFilteredDisplayItemsQuery = query
        cachedFilteredDisplayItemsRevision = searchRevision
        cachedFilteredDisplayItemsResult = result
        return result
    }
    
    // MARK: - 應用程式操作
    
    /// 啟動應用程式
    /// - Parameter app: 要啟動的應用程式
    func launchApp(_ app: AppItem) {
        Logger.info("Launching app: \(app.name)")
        
        launcherService.launchAsync(app) { [weak self] success in
            if success {
                Logger.info("Successfully launched: \(app.name)")
            } else {
                let errorMsg = "Failed to launch: \(app.name)"
                Logger.error(errorMsg)
                self?.errorMessage = errorMsg
            }
        }
    }
    
    /// 重設自訂排序與文件夾，恢復為依名稱排序。
    func resetLayout() {
        saveOrderWorkItem?.cancel()
        defaults.removeObject(forKey: orderKey)
        defaults.removeObject(forKey: foldersKey)
        
        folders.removeAll()
        displayItems = defaultSortedDisplayItems()
        
        saveOrderWorkItem?.cancel()
        saveOrderImmediately()
        Logger.info("Reset launchpad layout to default alphabetical order")
    }
    
    // MARK: - 隐藏应用功能

    /// 切换应用的显示/隐藏状态
    /// - Parameter app: 要切换的应用
    /// - Note: 隐藏的应用保留在 `allApps` 中，仅从 `apps`/`displayItems` 过滤。
    func toggleAppVisibility(_ app: AppItem) {
        if isAppHidden(app) {
            hiddenApps.removeAll { $0 == app.stableIdentifier }
            Logger.info("App '\(app.displayName)' is now visible")
        } else {
            hiddenApps.append(app.stableIdentifier)
            Logger.info("App '\(app.displayName)' is now hidden")
        }
        // 同步 visible apps 與顯示列表
        apps = allApps.filter { !isAppHidden($0) }
        reconcileDisplayItems()
    }

    /// 检查应用是否被隐藏
    /// - Parameter app: 要检查的应用
    /// - Returns: 如果应用被隐藏返回 true，否则返回 false
    func isAppHidden(_ app: AppItem) -> Bool {
        hiddenApps.contains(app.stableIdentifier)
    }

    /// 供設定頁顯示的隱藏應用條目（含反查到的名字與路徑）。
    /// 反查優先序：allApps -> 僅以 stableIdentifier 為名。
    var hiddenAppEntries: [HiddenAppEntry] {
        let lookup = Dictionary(uniqueKeysWithValues: allApps.map { ($0.stableIdentifier, $0) })
        return hiddenApps.map { identifier in
            if let app = lookup[identifier] {
                return HiddenAppEntry(
                    id: identifier,
                    name: app.displayName,
                    path: app.path
                )
            }
            // 應用可能已被卸載或路徑消失，仍列出 stableIdentifier 供使用者辨識
            return HiddenAppEntry(id: identifier, name: identifier, path: nil)
        }
    }

    // MARK: - 自訂名稱功能

    /// 取得指定應用的展示名稱（自訂名稱優先，否則原始名稱）。
    func displayName(for app: AppItem) -> String {
        app.displayName
    }

    /// 重命名應用。傳入 `nil` 或空白字串即恢復原始名稱。
    /// 會持久化到 UserDefaults 並同步更新 `allApps`/`apps`/`displayItems` 中對應項目的 `customName`。
    func renameApp(_ app: AppItem, to newName: String?) {
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let effective: String? = trimmed.isEmpty ? nil : trimmed

        // 1. 持久化
        customNameStore.setCustomName(effective, for: app.stableIdentifier)

        // 2. 同步 in-memory AppItem 並刷新顯示
        applyCustomName(effective, toStableIdentifier: app.stableIdentifier)
        Logger.info("Renamed app '\(app.originalName)' -> '\(effective ?? app.originalName)'")
    }

    /// 把新的 customName 套用到 allApps/apps/folders/displayItems 中對應的 AppItem，
    /// 並重建搜尋索引與顯示列表。
    private func applyCustomName(_ customName: String?, toStableIdentifier identifier: String) {
        allApps = allApps.map { app in
            guard app.stableIdentifier == identifier else { return app }
            var copy = app
            copy.customName = customName
            return copy
        }
        apps = allApps.filter { !isAppHidden($0) }

        // 同步 folders 中的 app
        folders = folders.map { folder in
            var updated = folder
            updated.apps = updated.apps.map { app in
                guard app.stableIdentifier == identifier else { return app }
                var copy = app
                copy.customName = customName
                return copy
            }
            return updated
        }

        // 重建搜尋狀態與顯示列表
        let searchState = buildSearchState(from: apps)
        searchableApps = searchState.apps
        appsByStableIdentifier = searchState.appsByStableIdentifier
        appsByBundleIdentifier = searchState.appsByBundleIdentifier
        searchIndex = searchState.index
        invalidateSearchCaches()
        reconcileDisplayItems()
    }

    // MARK: - 自訂 App 來源

    /// 目前已加入的自訂 App 來源路徑。
    var customAppPaths: [URL] {
        customAppSourceStore.loadAll()
    }

    /// 新增一個自訂 App 來源路徑並重新掃描合併。
    func addCustomAppPath(_ url: URL) {
        guard customAppSourceStore.add(url) else { return }
        Logger.info("Added custom app source: \(url.path)")
        rescanKeepingDisplayOrder()
    }

    /// 移除一個自訂 App 來源路徑並重新掃描合併。
    func removeCustomAppPath(_ url: URL) {
        guard customAppSourceStore.remove(url) else { return }
        Logger.info("Removed custom app source: \(url.path)")
        rescanKeepingDisplayOrder()
    }

    /// 重新掃描並套用自訂名稱，保留既有的自訂排序與文件夾。
    private func rescanKeepingDisplayOrder() {
        isLoading = true
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let customPaths = self.customAppSourceStore.loadAll()
            let scannedApps = self.scannerService.scanInstalledApps(customAppPaths: customPaths)
            let customNames = self.customNameStore.loadAll()
            let allApps = scannedApps.map { app -> AppItem in
                var copy = app
                copy.customName = customNames[app.stableIdentifier]
                return copy
            }
            let apps = allApps.filter { !self.isAppHidden($0) }
            let searchState = self.buildSearchState(from: apps)

            DispatchQueue.main.async {
                self.allApps = allApps
                self.apps = apps
                self.searchableApps = searchState.apps
                self.appsByStableIdentifier = searchState.appsByStableIdentifier
                self.appsByBundleIdentifier = searchState.appsByBundleIdentifier
                self.searchIndex = searchState.index
                self.invalidateSearchCaches()
                self.reconcileDisplayItems()
                self.isLoading = false
            }
        }
    }

    // MARK: - 卸載後資料清理

    /// 應用卸載成功後呼叫：從 allApps/apps/displayItems/folders 移除，
    /// 並清除對應的自訂名稱與隱藏紀錄。
    func removeAppFromLaunchpad(_ app: AppItem) {
        let identifier = app.stableIdentifier

        // 清除自訂名稱
        customNameStore.removeCustomName(for: identifier)
        // 清除隱藏紀錄
        hiddenApps.removeAll { $0 == identifier }

        // 從 allApps / apps 移除
        allApps.removeAll { $0.stableIdentifier == identifier }
        apps.removeAll { $0.stableIdentifier == identifier }

        // 從 folders 移除（含空文件夾清理）
        folders = folders.compactMap { folder -> AppFolder? in
            var updated = folder
            updated.apps.removeAll { $0.stableIdentifier == identifier }
            return updated.apps.isEmpty ? nil : updated
        }

        // 重建搜尋狀態與顯示列表
        let searchState = buildSearchState(from: apps)
        searchableApps = searchState.apps
        appsByStableIdentifier = searchState.appsByStableIdentifier
        appsByBundleIdentifier = searchState.appsByBundleIdentifier
        searchIndex = searchState.index
        invalidateSearchCaches()
        reconcileDisplayItems()

        Logger.info("Removed app '\(app.displayName)' from launchpad data after uninstall")
    }

    // MARK: - 排序和文件夾管理

    /// 移動項目到新位置
    func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < displayItems.count,
              destinationIndex >= 0, destinationIndex <= displayItems.count else {
            Logger.debug("moveItem: invalid indices source=\(sourceIndex), dest=\(destinationIndex), count=\(displayItems.count)")
            return
        }
        
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            let item = displayItems.remove(at: sourceIndex)
            displayItems.insert(item, at: min(adjustedDestination, displayItems.count))
        }
        
        Logger.info("Moved item from \(sourceIndex) to \(adjustedDestination)")
    }

    func moveItem(withId id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = indexOfItem(withId: id) else {
            Logger.debug("moveItem(withId:): missing source item \(id)")
            return
        }
        
        moveItem(from: sourceIndex, to: destinationIndex)
    }
    
    /// 創建新文件夾（將兩個應用合併，在目標位置插入文件夾）
    @discardableResult
    func createFolder(app1: AppItem, app2: AppItem) -> AppFolder {
        let folder = AppFolder(
            name: "New Folder",
            apps: [app1, app2]
        )
        
        folders.append(folder)
        
        if let targetIndex = displayItems.firstIndex(where: {
            if case .app(let app) = $0 { return app.id == app1.id }
            return false
        }) {
            let idsToRemove = Set([app1.id, app2.id])
            let removedBeforeTarget = displayItems[..<targetIndex].reduce(into: 0) { partialResult, item in
                if idsToRemove.contains(item.id) {
                    partialResult += 1
                }
            }
            displayItems.removeAll { idsToRemove.contains($0.id) }
            let insertionIndex = max(0, targetIndex - removedBeforeTarget)
            displayItems.insert(.folder(folder), at: min(insertionIndex, displayItems.count))
        } else {
            reconcileDisplayItems()
        }
        
        Logger.info("Created folder '\(folder.name)' with apps: \(app1.name), \(app2.name)")
        return folder
    }
    
    /// 將應用添加到現有文件夾
    func addAppToFolder(app: AppItem, folder: AppFolder) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }
        
        var updatedFolder = folders[folderIndex]
        
        // 檢查應用是否已在文件夾中
        guard !updatedFolder.apps.contains(where: { $0.id == app.id }) else {
            return
        }
        
        updatedFolder.apps.append(app)
        folders[folderIndex] = updatedFolder
        displayItems.removeAll { $0.id == app.id }
        
        if let folderDisplayIndex = displayItems.firstIndex(where: {
            if case .folder(let existingFolder) = $0 {
                return existingFolder.id == folder.id
            }
            return false
        }) {
            displayItems[folderDisplayIndex] = .folder(updatedFolder)
        } else {
            reconcileDisplayItems()
        }
        
        Logger.info("Added \(app.name) to folder '\(folder.name)'")
    }
    
    /// 從文件夾中移除應用（通用方法，支援多種場景）
    /// - Parameters:
    ///   - app: 要移除的應用
    ///   - folder: 目標文件夾
    ///   - placement: 移除後的放置方式
    func removeAppFromFolder(app: AppItem, folder: AppFolder, placement: FolderRemovalPlacement = .updateDisplay) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }
        
        var updatedFolder = folders[folderIndex]
        updatedFolder.apps.removeAll { $0.id == app.id }
        
        let folderDisplayIndex = displayItems.firstIndex {
            if case .folder(let f) = $0 { return f.id == folder.id }
            return false
        }
        
        // 處理文件夾刪除邏輯
        if updatedFolder.apps.count <= 1 {
            let lastApp = updatedFolder.apps.first
            folders.remove(at: folderIndex)
            
            if let idx = folderDisplayIndex {
                displayItems.remove(at: idx)
                // 如果有剩餘的 app，根據放置方式處理
                if let lastApp = lastApp {
                    switch placement {
                    case .updateDisplay:
                        displayItems.insert(.app(lastApp), at: idx)
                    case .floatingDrag:
                        displayItems.insert(.app(lastApp), at: idx)
                    case .appendToEnd:
                        displayItems.append(.app(lastApp))
                    }
                }
            }
        } else {
            folders[folderIndex] = updatedFolder
            if let idx = folderDisplayIndex {
                displayItems[idx] = .folder(updatedFolder)
            }
        }
        
        // 根據放置方式處理被移出的應用
        switch placement {
        case .updateDisplay:
            if let idx = folderDisplayIndex {
                let safeIndex = min(idx + 1, displayItems.count)
                displayItems.insert(.app(app), at: safeIndex)
            } else {
                displayItems.append(.app(app))
            }
            reconcileDisplayItems()
        case .floatingDrag:
            break  // 不做額外處理，讓浮動拖曳邏輯自己決定
        case .appendToEnd:
            displayItems.append(.app(app))
        }
        
        Logger.info("Removed \(app.name) from folder '\(folder.name)' with placement: \(placement)")
    }
    
    /// 放置方式枚舉
    enum FolderRemovalPlacement {
        case updateDisplay      // 正常移除並更新顯示
        case floatingDrag       // 浮動拖曳模式（不更新顯示）
        case appendToEnd        // 移到列表末尾
    }
    
    /// 將應用插入到指定位置
    func insertAppAt(app: AppItem, index: Int) {
        displayItems.removeAll { $0.id == app.id }
        let safeIndex = min(max(0, index), displayItems.count)
        displayItems.insert(.app(app), at: safeIndex)
        Logger.info("Inserted \(app.name) at index \(safeIndex)")
    }
    
    /// 重新排序文件夾內的應用
    func reorderAppsInFolder(_ folder: AppFolder, from sourceIndex: Int, to destinationIndex: Int) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folder.id }),
              sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < folders[folderIndex].apps.count,
              destinationIndex >= 0, destinationIndex < folders[folderIndex].apps.count else {
            return
        }
        
        var updatedFolder = folders[folderIndex]
        let app = updatedFolder.apps.remove(at: sourceIndex)
        updatedFolder.apps.insert(app, at: destinationIndex)
        folders[folderIndex] = updatedFolder
        
        // 更新 displayItems 中的文件夾
        if let displayIndex = displayItems.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == folder.id }
            return false
        }) {
            displayItems[displayIndex] = .folder(updatedFolder)
        } else {
            reconcileDisplayItems()
        }
        
        Logger.info("Reordered apps in folder '\(folder.name)': moved from \(sourceIndex) to \(destinationIndex)")
    }
    
    /// 重命名文件夾
    func renameFolder(_ folder: AppFolder, to newName: String) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }
        
        var updatedFolder = folders[folderIndex]
        updatedFolder.name = newName
        folders[folderIndex] = updatedFolder
        reconcileDisplayItems()
        
        Logger.info("Renamed folder to '\(newName)'")
    }
    
    /// 刪除文件夾（應用會回到主畫面）
    func deleteFolder(_ folder: AppFolder) {
        let reinsertionIndex = displayItems.firstIndex {
            if case .folder(let existingFolder) = $0 {
                return existingFolder.id == folder.id
            }
            return false
        } ?? displayItems.count
        
        folders.removeAll { $0.id == folder.id }
        displayItems.removeAll {
            if case .folder(let existingFolder) = $0 {
                return existingFolder.id == folder.id
            }
            return false
        }
        
        var currentIndex = reinsertionIndex
        for app in folder.apps {
            displayItems.insert(.app(app), at: min(currentIndex, displayItems.count))
            currentIndex += 1
        }
        
        reconcileDisplayItems()
        Logger.info("Deleted folder '\(folder.name)'")
    }
    
    /// 根據 ID 查找顯示項目的索引
    func indexOfItem(withId id: UUID) -> Int? {
        displayItems.firstIndex { $0.id == id }
    }
}

/// 供設定頁顯示的隱藏應用條目。
struct HiddenAppEntry: Identifiable, Hashable {
    /// stableIdentifier（bundleID 優先，否則 path）
    let id: String
    /// 展示名稱（自訂名稱優先，否則原始名稱；找不到時退回 id）
    let name: String
    /// 安裝路徑，若應用已被移除則為 `nil`
    let path: String?
}
