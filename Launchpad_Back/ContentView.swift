//
//  ContentView.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 2025/1/14.
//

import SwiftUI
import AppKit

enum ViewLayoutMode: String, CaseIterable {
    case horizontalPaging = "horizontalPaging"
    case verticalScroll = "verticalScroll"
}

private struct FloatingDragState {
    var draggingItemId: UUID?
    var item: LaunchpadDisplayItem?
    var location: CGPoint = .zero
    var startedInGrid = false
    var dropTargetId: UUID?
    var dropTargetIndex: Int = -1

    mutating func clear() {
        draggingItemId = nil
        item = nil
        location = .zero
        startedInGrid = false
        dropTargetId = nil
        dropTargetIndex = -1
    }
}

struct ContentView: View {
    @StateObject private var launchpadVM = LaunchpadViewModel()
    @StateObject private var searchVM = SearchViewModel()
    @StateObject private var paginationVM = PaginationViewModel()
    @StateObject private var editModeManager = EditModeManager()
    @AppStorage("viewLayoutMode") var viewLayoutMode: ViewLayoutMode = .horizontalPaging

    /// 每次外观设置（图标大小/每行数/显示名称）变化时递增，
    /// 用作 LaunchpadView 的 id，强制 SwiftUI 完全重建子视图树
    @State private var layoutVersion: Int = 0

    var body: some View {
        LaunchpadView()
            .id(layoutVersion)
            .environmentObject(launchpadVM)
            .environmentObject(searchVM)
            .environmentObject(paginationVM)
            .environmentObject(editModeManager)
            .environment(\.viewLayoutMode, viewLayoutMode)
            .onReceive(NotificationCenter.default.publisher(for: .viewLayoutModeChanged)) { notification in
                if let newMode = notification.object as? ViewLayoutMode {
                    viewLayoutMode = newMode
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .layoutSettingsChanged)) { _ in
                // 清空布局缓存，并通过递增 layoutVersion 强制 SwiftUI 重建视图
                paginationVM.invalidateLayout()
                layoutVersion += 1
            }
    }
}

private struct ViewLayoutModeKey: EnvironmentKey {
    static var defaultValue: ViewLayoutMode = .horizontalPaging
}

extension EnvironmentValues {
    var viewLayoutMode: ViewLayoutMode {
        get { self[ViewLayoutModeKey.self] }
        set { self[ViewLayoutModeKey.self] = newValue }
    }
}

struct LaunchpadView: View {
    @EnvironmentObject var launchpadVM: LaunchpadViewModel
    @EnvironmentObject var searchVM: SearchViewModel
    @EnvironmentObject var paginationVM: PaginationViewModel
    @EnvironmentObject var editModeManager: EditModeManager
    @Environment(\.viewLayoutMode) var viewLayoutMode

    @State private var dragAmount = CGSize.zero
    @State private var keyboardManager: KeyboardEventManager?
    @State private var gestureManager: GestureManager?
    @State private var expandedFolder: AppFolder?
    @State private var showingResetConfirmation = false
    @State private var floatingDragState = FloatingDragState()
    /// 垂直滚动模式下，网格在全局坐标空间中的 frame（随滚动更新）。
    /// 用于在垂直模式计算拖放落点目标（替代分页布局）。
    @State private var verticalGridFrame: CGRect = .zero
    /// 当前是否处于三指拖动中。用于区分三指拖动源与编辑模式拖动：
    /// 三指拖动不进编辑模式，拖完直接 drop；该标志阻止 onDragChanged/onDragEnded
    /// 在三指拖动进行时被编辑模式手势重复处理。
    @State private var threeFingerDragActive = false
    /// 最近一次 GeometryReader 报告的尺寸。三指拖动通知处理器在视图树外触发，
    /// 拿不到 GeometryProxy，用此缓存计算 currentGridLayout / 边缘换页 / 落点目标。
    @State private var lastGeometrySize: CGSize = .zero
    /// 落点计算节流时间戳（30ms 节流，避免 125-250Hz 全频遍历）
    @State private var lastDropTargetCheckTime: TimeInterval = 0

    private var filteredItems: [LaunchpadDisplayItem] {
        launchpadVM.filteredDisplayItems(matching: searchVM.searchText)
    }

    /// 顶部留白：全屏模式下多留空间避开灵动岛/菜单栏，窗口模式下少留
    private var topPadding: CGFloat {
        let mode = WindowMode(rawValue: UserDefaults.standard.string(forKey: "windowMode") ?? "")
            ?? .fullscreen
        return mode == .fullscreen ? 50 : 6
    }

    private var totalPages: Int {
        paginationVM.totalPages(for: filteredItems.count)
    }

    private var renderedPageIndices: [Int] {
        guard totalPages > 0 else { return [] }
        
        let lowerBound = max(0, paginationVM.currentPage - 1)
        let upperBound = min(totalPages - 1, paginationVM.currentPage + 1)
        return Array(lowerBound...upperBound)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景：allowsHitTesting(false) 让 NSVisualEffectView 只负责渲染，不参与命中
                LaunchpadBackgroundView()
                    .allowsHitTesting(false)

                // 空白点击捕获层：覆盖全屏，图标在上层优先命中，空白处落到本层
                Rectangle()
                    .fill(Color.clear)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleEscapeKey()
                    }

                VStack(spacing: 0) {
                    // 頂部間距：全屏模式下留更多空间避开灵动岛/菜单栏区域
                    Spacer().frame(height: topPadding)

                    // 搜尋欄（編輯模式時隱藏）
                    if !editModeManager.isEditing {
                        normalHeaderView

                        Spacer().frame(height: 4)
                    } else {
                        editingHeaderView

                        Spacer().frame(height: 4)
                    }

                    // 應用程式網格（去掉全屏 contentShape + DragGesture，让空白点击能穿透到捕获层）
                    if viewLayoutMode == .horizontalPaging {
                        ZStack {
                            ForEach(renderedPageIndices, id: \.self) { pageIndex in
                                PageViewEditable(
                                    items: paginationVM.itemsForPage(filteredItems, page: pageIndex),
                                    layoutConfig: paginationVM.layoutConfig,
                                    pageIndex: pageIndex,
                                    currentPage: paginationVM.currentPage,
                                    screenWidth: geometry.size.width,
                                    dragAmount: editModeManager.isEditing ? .zero : dragAmount,
                                    isEditing: editModeManager.isEditing,
                                    draggingItemId: floatingDragState.draggingItemId,
                                    dropTargetId: floatingDragState.dropTargetId,
                                    onItemTap: { item in
                                        switch item {
                                        case .app(let app):
                                            if !editModeManager.isEditing {
                                                hideWindow()
                                                launchpadVM.launchApp(app)
                                            }
                                        case .folder(let folder):
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                expandedFolder = folder
                                            }
                                        }
                                    },
                                    onLongPress: {
                                        editModeManager.enterEditMode()
                                    },
                                    onDragChanged: { itemId, location in
                                        // 三指拖动进行中：忽略 SwiftUI 单指/长按拖动事件，避免状态冲突
                                        guard !threeFingerDragActive else { return }
                                        if floatingDragState.item == nil,
                                           let item = filteredItems.first(where: { $0.id == itemId }) {
                                            floatingDragState.item = item
                                            floatingDragState.startedInGrid = true
                                        }

                                        floatingDragState.location = location
                                        floatingDragState.draggingItemId = itemId

                                        _ = checkEdgeForPageChange(screenLocation: location, geometry: geometry)

                                        let result = findDropTargetByScreenLocation(at: location, excludingId: itemId, in: geometry)
                                        floatingDragState.dropTargetId = result.targetId
                                        floatingDragState.dropTargetIndex = result.targetIndex
                                    },
                                    onDragEnded: { _ in
                                        // 三指拖动进行中：忽略 SwiftUI 单指/长按拖动结束
                                        guard !threeFingerDragActive else { return }
                                        handleFloatingDrop()
                                        floatingDragState.clear()
                                    }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VerticalScrollView(
                            items: filteredItems,
                            layoutConfig: paginationVM.layoutConfig,
                            isEditing: editModeManager.isEditing,
                            draggingItemId: floatingDragState.draggingItemId,
                            dropTargetId: floatingDragState.dropTargetId,
                            onItemTap: { item in
                                switch item {
                                case .app(let app):
                                    if !editModeManager.isEditing {
                                        hideWindow()
                                        launchpadVM.launchApp(app)
                                    }
                                case .folder(let folder):
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        expandedFolder = folder
                                    }
                                }
                            },
                            onLongPress: {
                                editModeManager.enterEditMode()
                            },
                            onDragChanged: { itemId, location in
                                // 三指拖动进行中：忽略 SwiftUI 单指/长按拖动事件，避免状态冲突
                                guard !threeFingerDragActive else { return }
                                if floatingDragState.item == nil,
                                   let item = filteredItems.first(where: { $0.id == itemId }) {
                                    floatingDragState.item = item
                                    floatingDragState.startedInGrid = true
                                }

                                floatingDragState.location = location
                                floatingDragState.draggingItemId = itemId

                                let result = findDropTargetByScreenLocation(at: location, excludingId: itemId, in: geometry)
                                floatingDragState.dropTargetId = result.targetId
                                floatingDragState.dropTargetIndex = result.targetIndex
                            },
                            onDragEnded: { _ in
                                // 三指拖动进行中：忽略 SwiftUI 单指/长按拖动结束
                                guard !threeFingerDragActive else { return }
                                handleFloatingDrop()
                                floatingDragState.clear()
                            },
                            onGridFrameChanged: { frame in
                                // 仅当 frame 真正变化时更新，避免空闲滚动期间频繁重渲染
                                if frame != verticalGridFrame {
                                    verticalGridFrame = frame
                                }
                            }
                        )
                    }
                    
                    // 頁面指示器（仅水平分页模式显示；垂直模式无分页概念）
                    if viewLayoutMode == .horizontalPaging && totalPages > 1 && searchVM.searchText.isEmpty {
                        PageIndicatorView(
                            currentPage: paginationVM.currentPage,
                            totalPages: totalPages,
                            onPageTap: { page in
                                paginationVM.jumpToPage(page, totalPages: totalPages)
                                dragAmount = .zero
                            }
                        )
                        .padding(.bottom, 6)
                    } else {
                        Spacer().frame(height: 6)
                    }
                }
                
                // 展開的文件夾視圖
                if let folder = expandedFolder {
                    FolderExpandedView(
                        folder: folder,
                        onAppTap: { app in
                            expandedFolder = nil
                            hideWindow()
                            launchpadVM.launchApp(app)
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                expandedFolder = nil
                            }
                        },
                        onRename: { newName in
                            launchpadVM.renameFolder(folder, to: newName)
                            if let updatedFolder = launchpadVM.folders.first(where: { $0.id == folder.id }) {
                                expandedFolder = updatedFolder
                            }
                        },
                        onReorder: { fromIndex, toIndex in
                            launchpadVM.reorderAppsInFolder(folder, from: fromIndex, to: toIndex)
                            if let updatedFolder = launchpadVM.folders.first(where: { $0.id == folder.id }) {
                                expandedFolder = updatedFolder
                            }
                        },
                        onStartDragOut: { app, screenLocation in
                            floatingDragState.item = .app(app)
                            floatingDragState.location = screenLocation
                            floatingDragState.startedInGrid = false

                            launchpadVM.removeAppFromFolder(app: app, folder: folder, placement: .floatingDrag)
                            editModeManager.enterEditMode()

                            // 拖出瞬间立即收起文件夹，露出下方网格让用户看清放置位置。
                            // 之前只在 onDragOutEnd（松手时）才收起，导致拖动过程文件夹一直挡住网格。
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                expandedFolder = nil
                            }
                        },
                        onDragOutContinue: { screenLocation in
                            floatingDragState.location = screenLocation
                            _ = checkEdgeForPageChange(screenLocation: screenLocation, geometry: geometry)

                            if let item = floatingDragState.item {
                                let result = findDropTargetByScreenLocation(at: screenLocation, excludingId: item.id, in: geometry)
                                floatingDragState.dropTargetId = result.targetId
                                floatingDragState.dropTargetIndex = result.targetIndex
                            }
                        },
                        onDragOutEnd: {
                            handleFloatingDrop()
                            floatingDragState.clear()

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                expandedFolder = nil
                            }
                        },
                        initialEditingMode: editModeManager.isEditing
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                // 蓝色插入指示器（独立渲染，三指拖动和长按拖动都显示）
                if floatingDragState.item != nil && floatingDragState.dropTargetIndex >= 0 {
                    screenLocationDropIndicator(at: floatingDragState.dropTargetIndex, in: geometry)
                }

                // 浮動拖曳的 icon（跟著滑鼠）
                // 三指拖动时 AppKit overlay 负责视觉，不显示 SwiftUI 版本（避免高频重渲染）
                if let item = floatingDragState.item, !threeFingerDragActive {
                    floatingDragOverlay(item: item, location: floatingDragState.location, in: geometry)
                }
            }
            // 分页拖动移到外层 ZStack，释放网格区域的命中（避免 contentShape 拦截空白点击）
            // 三指拖动进行中禁用分页拖动，避免拖图标时整个页面跟着移动
            .gesture(
                (viewLayoutMode == .horizontalPaging && !editModeManager.isEditing && !threeFingerDragActive) ?
                DragGesture(minimumDistance: 20)
                    .onChanged { dragAmount = $0.translation }
                    .onEnded(handleDragEnd) : nil
            )
            .alert("reset_layout_title", isPresented: $showingResetConfirmation) {
                Button("cancel", role: .cancel) {}
                Button("reset", role: .destructive) {
                    resetLayout()
                }
            } message: {
                Text("reset_layout_message")
            }
            .onAppear {
                paginationVM.updateScreenSize(geometry.size)
                launchpadVM.loadInstalledApps()
                launchpadVM.updateActivePage(paginationVM.currentPage, itemsPerPage: paginationVM.appsPerPage)
                lastGeometrySize = geometry.size
                setupEventManagers()
            }
            .onChange(of: geometry.size) { _, newSize in
                paginationVM.updateScreenSize(newSize)
                paginationVM.validateCurrentPage(totalPages: totalPages)
                launchpadVM.updateActivePage(paginationVM.currentPage, itemsPerPage: paginationVM.appsPerPage)
                // 同步缓存供三指拖动通知处理器使用
                lastGeometrySize = newSize
            }
            .onChange(of: paginationVM.currentPage) { _, newPage in
                launchpadVM.updateActivePage(newPage, itemsPerPage: paginationVM.appsPerPage)
            }
            .onChange(of: totalPages) { _, _ in
                paginationVM.validateCurrentPage(totalPages: totalPages)
                launchpadVM.updateActivePage(paginationVM.currentPage, itemsPerPage: paginationVM.appsPerPage)
            }
            // 三指拖动：订阅 Coordinator 派发的通知（已切主线程），驱动状态机。
            // 用 onReceive 而非手动 addObserver，避免 struct self 捕获问题，
            // SwiftUI 自动随视图生命周期管理订阅。
            .onReceive(NotificationCenter.default.publisher(for: .threeFingerDragUIEvent)) { notification in
                guard let event = notification.object as? ThreeFingerDragUIEvent else { return }
                handleThreeFingerDragEvent(event)
            }
            .onDisappear {
                teardownEventManagers()
                // 视图消失时若仍在三指拖动中，复位状态避免悬挂
                threeFingerDragActive = false
            }
        }
    }

    private var normalHeaderView: some View {
        SearchBarView(text: $searchVM.searchText)
            .onChange(of: searchVM.searchText) { _, _ in
                paginationVM.reset()
                dragAmount = .zero
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                HStack(spacing: 8) {
                    scrollModeToggle
                    resetLayoutButton
                    settingsButton
                }
                .padding(.trailing, 40)
            }
    }

    private var editingHeaderView: some View {
        HStack {
            Text("drag_to_rearrange")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            scrollModeToggle

            resetLayoutButton

            settingsButton

            Button("done") {
                editModeManager.exitEditMode()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.2)))
        }
        .padding(.horizontal, 40)
        .padding(.top, 5)
    }

    private var settingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(Circle().fill(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help("settings")
    }

    @ViewBuilder
    private var scrollModeToggle: some View {
        Menu {
            ForEach(ViewLayoutMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation {
                        // 通过环境更新，需要从更高层获取binding
                        // 这里使用通知中心或其他方式来更新
                        NotificationCenter.default.post(name: .viewLayoutModeChanged, object: mode)
                    }
                } label: {
                    HStack {
                        Text(mode == .horizontalPaging ? LocalizedStringKey("horizontal_paging") : LocalizedStringKey("vertical_scroll"))
                        if viewLayoutMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(viewLayoutMode == .horizontalPaging ? LocalizedStringKey("horizontal_paging") : LocalizedStringKey("vertical_scroll"),
                  systemImage: viewLayoutMode == .horizontalPaging ? "rectangle.2.group" : "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }

    private var resetLayoutButton: some View {
        Button {
            showingResetConfirmation = true
        } label: {
            Label("reset_layout", systemImage: "arrow.counterclockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .disabled(launchpadVM.isLoading || launchpadVM.apps.isEmpty)
        .opacity((launchpadVM.isLoading || launchpadVM.apps.isEmpty) ? 0.5 : 1)
    }
    
    // MARK: - 浮動拖曳視圖
    
    @ViewBuilder
    private func floatingDragOverlay(item: LaunchpadDisplayItem, location: CGPoint, in geometry: GeometryProxy) -> some View {
        ZStack {
            // 跟隨滑鼠的圖標
            VStack(spacing: 4) {
                switch item {
                case .app(let app):
                    CachedAppIconImage(path: app.path, appName: app.name) {
                        IconLoadingPlaceholder(cornerRadius: 14)
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    Text(app.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                case .folder(let folder):
                    // 簡化的文件夾圖標（用於拖曳）
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .frame(width: 60, height: 60)
                        .overlay(
                            LazyVGrid(columns: [GridItem(.fixed(16)), GridItem(.fixed(16)), GridItem(.fixed(16))], spacing: 2) {
                                ForEach(folder.apps.prefix(9), id: \.id) { app in
                                    CachedAppIconImage(path: app.path, appName: app.name) {
                                        IconLoadingPlaceholder(cornerRadius: 3)
                                    }
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .padding(4)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 8)
                    Text(folder.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .position(location)
        }
    }
    
    // MARK: - 跨頁拖動支援
    
    // 邊緣檢測狀態
    @State private var lastEdgeCheckTime: Date = .distantPast
    @State private var lastEdgeDirection: Int = 0  // -1: 左, 0: 無, 1: 右
    @State private var isWaitingForEdgeExit: Bool = false  // 等待離開邊緣

    private func currentGridLayout(in geometry: GeometryProxy) -> GridScreenLayout {
        currentGridLayout(size: geometry.size)
    }

    /// 仅依赖 CGSize 的重载，供三指拖动通知处理器（拿不到 GeometryProxy）复用。
    private func currentGridLayout(size: CGSize) -> GridScreenLayout {
        let layoutConfig = paginationVM.layoutConfig

        // 垂直滚动模式：网格 frame 由 VerticalScrollView 上报（已含滚动位移），
        // 用全量 items 计算行数，而非单页行数
        if viewLayoutMode == .verticalScroll {
            let totalRows = max(1, Int(ceil(Double(filteredItems.count) / Double(layoutConfig.columns))))
            let gridHeight = GridLayoutManager.gridHeight(rowCount: totalRows)
            // verticalGridFrame 为全局坐标；保持其 origin，高度补全为完整网格高度
            let frame = CGRect(
                origin: verticalGridFrame.origin,
                size: CGSize(width: layoutConfig.gridWidth, height: gridHeight)
            )
            return GridScreenLayout(
                frame: frame,
                columns: layoutConfig.columns,
                itemWidth: GridLayoutManager.itemWidth,
                itemHeight: GridLayoutManager.itemHeight,
                horizontalSpacing: GridLayoutManager.horizontalSpacing,
                verticalSpacing: GridLayoutManager.verticalSpacing
            )
        }

        // 水平分页模式：网格居中于可用区域
        let topAreaHeight = GridLayoutManager.headerAreaHeight
        let bottomAreaHeight = GridLayoutManager.footerAreaHeight
        let availableHeight = size.height - topAreaHeight - bottomAreaHeight
        let origin = CGPoint(
            x: (size.width - layoutConfig.gridWidth) / 2,
            y: topAreaHeight + (availableHeight - layoutConfig.gridHeight) / 2
        )

        return GridScreenLayout(
            frame: CGRect(origin: origin, size: CGSize(width: layoutConfig.gridWidth, height: layoutConfig.gridHeight)),
            columns: layoutConfig.columns,
            itemWidth: GridLayoutManager.itemWidth,
            itemHeight: GridLayoutManager.itemHeight,
            horizontalSpacing: GridLayoutManager.horizontalSpacing,
            verticalSpacing: GridLayoutManager.verticalSpacing
        )
    }
    
    /// 使用絕對螢幕位置檢測邊緣換頁
    private func checkEdgeForPageChange(screenLocation: CGPoint, geometry: GeometryProxy) -> (pageChanged: Bool, previousPage: Int) {
        checkEdgeForPageChange(screenLocation: screenLocation, screenWidth: geometry.size.width)
    }

    /// 仅依赖 screenWidth 的重载，供三指拖动通知处理器复用。
    private func checkEdgeForPageChange(screenLocation: CGPoint, screenWidth: CGFloat) -> (pageChanged: Bool, previousPage: Int) {
        let edgeThreshold: CGFloat = 50
        let previousPage = paginationVM.currentPage
        
        var currentDirection: Int = 0
        
        if screenLocation.x < edgeThreshold {
            currentDirection = -1
        } else if screenLocation.x > screenWidth - edgeThreshold {
            currentDirection = 1
        }
        
        // 如果正在等待離開邊緣
        if isWaitingForEdgeExit {
            if currentDirection == 0 {
                isWaitingForEdgeExit = false
                lastEdgeDirection = 0
            }
            return (false, previousPage)
        }
        
        if currentDirection == 0 {
            lastEdgeDirection = 0
            lastEdgeCheckTime = .distantPast
            return (false, previousPage)
        }
        
        if currentDirection != lastEdgeDirection {
            lastEdgeDirection = currentDirection
            lastEdgeCheckTime = Date()
            return (false, previousPage)
        }
        
        let now = Date()
        guard now.timeIntervalSince(lastEdgeCheckTime) > 0.3 else { return (false, previousPage) }
        
        var pageChanged = false
        
        if currentDirection == -1 && paginationVM.currentPage > 0 {
            isWaitingForEdgeExit = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                paginationVM.previousPage()
            }
            pageChanged = true
            Logger.info("Edge detected: switching to previous page (\(paginationVM.currentPage))")
        }
        else if currentDirection == 1 && paginationVM.currentPage < totalPages - 1 {
            isWaitingForEdgeExit = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                paginationVM.nextPage(totalPages: totalPages)
            }
            pageChanged = true
            Logger.info("Edge detected: switching to next page (\(paginationVM.currentPage))")
        }
        
        return (pageChanged, previousPage)
    }
    
    /// 使用絕對螢幕位置查找 drop target
    private func findDropTargetByScreenLocation(at screenLocation: CGPoint, excludingId: UUID, in geometry: GeometryProxy) -> (targetId: UUID?, targetIndex: Int) {
        findDropTargetByScreenLocation(at: screenLocation, excludingId: excludingId, size: geometry.size)
    }

    /// 仅依赖 CGSize 的重载，供三指拖动通知处理器复用。
    private func findDropTargetByScreenLocation(at screenLocation: CGPoint, excludingId: UUID, size: CGSize) -> (targetId: UUID?, targetIndex: Int) {
        let gridLayout = currentGridLayout(size: size)
        // 垂直模式使用全量 items（单列滚动，无分页）；水平模式仍按当前页命中
        let pageItems = viewLayoutMode == .verticalScroll
            ? filteredItems
            : paginationVM.itemsForPage(filteredItems, page: paginationVM.currentPage)

        guard let targetIndex = gridLayout.clampedIndex(
            at: screenLocation,
            itemCount: pageItems.count,
            allowsTrailingSlot: true
        ) else {
            return (nil, -1)
        }

        guard targetIndex < pageItems.count else {
            return (nil, targetIndex)
        }

        let targetItem = pageItems[targetIndex]
        guard targetItem.id != excludingId else {
            return (nil, -1)
        }

        if gridLayout.isNearItemCenter(
            at: screenLocation,
            index: targetIndex,
            horizontalRatio: 0.35,
            verticalRatio: 0.35,
            visualHeight: GridLayoutManager.iconSize
        ) {
            Logger.debug("findDropTargetByScreen: found target \(targetItem.name) at index \(targetIndex)")
            return (targetItem.id, targetIndex)
        }

        Logger.debug("findDropTargetByScreen: reorder to index \(targetIndex)")
        return (nil, targetIndex)
    }
    
    /// 螢幕位置的放置指示器
    @ViewBuilder
    private func screenLocationDropIndicator(at index: Int, in geometry: GeometryProxy) -> some View {
        let position = currentGridLayout(in: geometry).leadingIndicatorPosition(at: index)
        
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.blue)
            .frame(width: 4, height: GridLayoutManager.itemHeight)
            .shadow(color: .blue.opacity(0.5), radius: 4)
            .position(x: position.x, y: position.y)
    }
    
    /// 處理浮動拖曳放置
    private func handleFloatingDrop() {
        guard let item = floatingDragState.item else { return }

        let itemsPerPage = paginationVM.layoutConfig.itemsPerPage
        // 垂直模式无分页，目标索引即全局索引；水平模式需加上当前页偏移
        let pageOffset = viewLayoutMode == .verticalScroll ? 0 : paginationVM.currentPage * itemsPerPage
        let isFromGrid = floatingDragState.startedInGrid
        
        if let targetId = floatingDragState.dropTargetId,
           let targetItem = filteredItems.first(where: { $0.id == targetId }) {
            // 放到目標上 - 創建文件夾或添加到文件夾
            switch (item, targetItem) {
            case (.app(let draggedApp), .app(let targetApp)):
                _ = launchpadVM.createFolder(app1: targetApp, app2: draggedApp)
                Logger.info("Created folder with \(draggedApp.name) and \(targetApp.name)")
            case (.app(let draggedApp), .folder(let targetFolder)):
                launchpadVM.addAppToFolder(app: draggedApp, folder: targetFolder)
                Logger.info("Added \(draggedApp.name) to folder '\(targetFolder.name)'")
            case (.folder(_), .app(_)):
                // 文件夾拖到應用上 - 只做重新排序
                if isFromGrid && floatingDragState.dropTargetIndex >= 0 {
                    let targetGlobalIndex = pageOffset + floatingDragState.dropTargetIndex
                    launchpadVM.moveItem(withId: item.id, to: targetGlobalIndex)
                }
            case (.folder(_), .folder(_)):
                // 文件夾拖到文件夾上 - 只做重新排序
                if isFromGrid && floatingDragState.dropTargetIndex >= 0 {
                    let targetGlobalIndex = pageOffset + floatingDragState.dropTargetIndex
                    launchpadVM.moveItem(withId: item.id, to: targetGlobalIndex)
                }
            }
        } else if floatingDragState.dropTargetIndex >= 0 {
            // 放到空位 - 重新排序
            let targetGlobalIndex = pageOffset + floatingDragState.dropTargetIndex
            if isFromGrid {
                launchpadVM.moveItem(withId: item.id, to: targetGlobalIndex)
                Logger.info("Moved item \(item.id) to \(targetGlobalIndex)")
            } else {
                // 從文件夾拖出來的
                if case .app(let app) = item {
                    launchpadVM.insertAppAt(app: app, index: targetGlobalIndex)
                    Logger.info("Inserted \(app.name) at index \(targetGlobalIndex)")
                }
            }
        } else {
            // 沒有有效目標 - 放到末尾（僅對文件夾拖出的 app 有效）
            if !isFromGrid {
                if case .app(let app) = item {
                    launchpadVM.insertAppAt(app: app, index: launchpadVM.displayItems.count)
                    Logger.info("Inserted \(app.name) at end")
                }
            }
        }

        floatingDragState.clear()
    }
    
    // MARK: - Private Methods
    
    private func setupEventManagers() {
        keyboardManager = KeyboardEventManager(
            onLeftArrow: { paginationVM.previousPage() },
            onRightArrow: { paginationVM.nextPage(totalPages: totalPages) },
            onEscape: handleEscapeKey,
            onCommandW: hideWindow,
            onCommandQ: quitApp
        )
        keyboardManager?.startListening()
        
        gestureManager = GestureManager { [weak paginationVM, weak launchpadVM, weak searchVM] direction in
            guard let paginationVM = paginationVM,
                  let launchpadVM = launchpadVM,
                  let searchVM = searchVM else { return }
            
            let filteredCount = launchpadVM.filteredDisplayItems(matching: searchVM.searchText).count
            let totalPages = paginationVM.totalPages(for: filteredCount)
            
            Logger.debug("Page change requested: direction=\(direction), currentPage=\(paginationVM.currentPage), totalPages=\(totalPages)")

            if direction > 0 {
                paginationVM.nextPage(totalPages: totalPages)
            } else {
                paginationVM.previousPage()
            }
        }
        gestureManager?.startListening()
    }

    // MARK: - 三指拖动状态机

    /// 三指拖动事件分发入口。
    /// - begin: 反查指针下图标作为 draggingItem，复用 onDragChanged 逻辑，
    ///          不进编辑模式。
    /// - change: 更新浮动图标位置 + 落点目标（含边缘换页）。
    /// - end: 调 handleFloatingDrop 并清理（不进编辑模式）。
    private func handleThreeFingerDragEvent(_ event: ThreeFingerDragUIEvent) {
        switch event {
        case .begin(let mouseLocation):
            beginThreeFingerDrag(at: mouseLocation)
        case .change(let mouseLocation):
            updateThreeFingerDrag(to: mouseLocation)
        case .end:
            endThreeFingerDrag()
        }
    }

    /// 三指拖动开始：用鼠标位置反查指针下图标，设为 draggingItem。
    /// 不进编辑模式（区别于长按拖动）。
    private func beginThreeFingerDrag(at mouseLocation: CGPoint) {
        // 若已有正在进行的拖动（编辑模式或上次三指拖动未清理），先收尾
        if floatingDragState.item != nil {
            handleFloatingDrop()
            floatingDragState.clear()
            FloatingIconOverlayController.shared.end()
        }

        // 文件夹展开时：优先在文件夹内反查图标，命中则走"拖出文件夹"逻辑
        if let folder = expandedFolder,
           let (app, _) = findFolderItemAtScreenLocation(at: mouseLocation, in: folder) {
            floatingDragState.item = .app(app)
            floatingDragState.draggingItemId = app.id
            floatingDragState.startedInGrid = false
            // 不设 floatingDragState.location（由 AppKit overlay 处理视觉位置）
            threeFingerDragActive = true

            launchpadVM.removeAppFromFolder(app: app, folder: folder, placement: .floatingDrag)
            editModeManager.enterEditMode()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                expandedFolder = nil
            }

            // 启动 AppKit 浮动图标层（不走 SwiftUI 重渲染）
            let icon = AppIconCache.shared.cachedIcon(for: app.path)
                ?? NSWorkspace.shared.icon(forFile: app.path)
            FloatingIconOverlayController.shared.begin(icon: icon, appName: app.displayName, at: mouseLocation)
            Logger.info("ThreeFingerDrag: 从文件夹拖出 \(app.name)")
            return
        }

        guard let item = findItemAtScreenLocation(at: mouseLocation) else {
            threeFingerDragActive = true
            Logger.debug("ThreeFingerDrag: begin 但指针下无图标，进入待命状态")
            return
        }

        floatingDragState.item = item
        floatingDragState.draggingItemId = item.id
        floatingDragState.startedInGrid = true
        // 不设 floatingDragState.location（由 AppKit overlay 处理视觉位置）
        threeFingerDragActive = true

        let dropResult = findDropTargetByScreenLocation(at: mouseLocation,
                                                        excludingId: item.id,
                                                        size: lastGeometrySize)
        floatingDragState.dropTargetId = dropResult.targetId
        floatingDragState.dropTargetIndex = dropResult.targetIndex

        // 启动 AppKit 浮动图标层（不走 SwiftUI 重渲染）
        if case .app(let app) = item {
            // 优先用已缓存的高分辨率图标；若缓存未命中（首次拖动）则同步从 NSWorkspace 加载真实图标
            let icon = AppIconCache.shared.cachedIcon(for: app.path)
                ?? NSWorkspace.shared.icon(forFile: app.path)
            FloatingIconOverlayController.shared.begin(icon: icon, appName: app.displayName, at: mouseLocation)
        }
        Logger.info("ThreeFingerDrag: 选中 \(item.name) 作为拖动源")
    }

    /// 三指拖动位置更新（高频，125-250Hz）：
    /// 【性能优化】location 更新完全绕过 SwiftUI，直接调 AppKit NSPanel.setFrameOrigin()。
    /// 不再写 floatingDragState.location（避免触发父视图重渲染）。
    /// 落点计算加时间节流（30ms），避免 125-250Hz 全频遍历网格。
    private func updateThreeFingerDrag(to mouseLocation: CGPoint) {
        guard threeFingerDragActive, let item = floatingDragState.item else { return }

        // 【核心优化】只更新 panel 位置，不触发任何 SwiftUI @State 变化
        FloatingIconOverlayController.shared.updateLocation(mouseLocation)

        // 边缘换页（仅水平分页模式）
        _ = checkEdgeForPageChange(screenLocation: mouseLocation, screenWidth: lastGeometrySize.width)

        // 落点计算：时间节流，每 30ms 算一次（约 33Hz，足够流畅），避免 125-250Hz 全频遍历
        let now = CACurrentMediaTime()
        guard now - lastDropTargetCheckTime >= 0.030 else { return }
        lastDropTargetCheckTime = now

        let result = findDropTargetByScreenLocation(at: mouseLocation,
                                                    excludingId: item.id,
                                                    size: lastGeometrySize)
        if result.targetId != floatingDragState.dropTargetId ||
           result.targetIndex != floatingDragState.dropTargetIndex {
            floatingDragState.dropTargetId = result.targetId
            floatingDragState.dropTargetIndex = result.targetIndex
        }
    }

    /// 三指拖动结束：直接 drop（不进编辑模式），关闭 AppKit overlay。
    private func endThreeFingerDrag() {
        guard threeFingerDragActive else { return }
        threeFingerDragActive = false

        // 关闭 AppKit 浮动图标层
        FloatingIconOverlayController.shared.end()

        if floatingDragState.item != nil {
            handleFloatingDrop()
        }
        floatingDragState.clear()
    }

    /// 在全局坐标(与 DragGesture.location 同空间)反查指针下图标。
    /// 多屏/scroll offset/page offset/搜索结果索引均由 currentGridLayout 与
    /// filteredItems/itemsForPage 自然覆盖，无需手动行列推算。
    /// - Parameter location: SwiftUI `.global` 坐标
    /// - Returns: 命中的 LaunchpadDisplayItem，未命中返回 nil
    private func findItemAtScreenLocation(at location: CGPoint) -> LaunchpadDisplayItem? {
        let gridLayout = currentGridLayout(size: lastGeometrySize)
        let pageItems = viewLayoutMode == .verticalScroll
            ? filteredItems
            : paginationVM.itemsForPage(filteredItems, page: paginationVM.currentPage)

        guard let rawIndex = gridLayout.rawIndex(at: location) else { return nil }
        guard rawIndex >= 0, rawIndex < pageItems.count else { return nil }

        let item = pageItems[rawIndex]
        // 命中检测：点落在该 item 的 cell 内即算命中（不必靠近中心，
        // 因为这里要的是"指针停在哪格"作为拖动源，而非落点）
        let center = gridLayout.itemCenter(at: rawIndex)
        let halfCellW = (gridLayout.itemWidth + gridLayout.horizontalSpacing) / 2
        let halfCellH = (gridLayout.itemHeight + gridLayout.verticalSpacing) / 2
        if abs(location.x - center.x) <= halfCellW &&
           abs(location.y - center.y) <= halfCellH {
            return item
        }
        return nil
    }

    /// 在展开的文件夹内反查指针下图标（用于三指拖动从文件夹拖出）。
    /// 布局算法对齐 FolderExpandedView.expandedLayout，确保命中一致。
    /// - Returns: 命中的 (app, folder内index)，未命中返回 nil
    private func findFolderItemAtScreenLocation(at location: CGPoint, in folder: AppFolder) -> (AppItem, Int)? {
        let folderColumns = 4
        let itemWidth = GridLayoutManager.itemWidth
        let itemHeight = GridLayoutManager.itemHeight
        let hSpacing = GridLayoutManager.horizontalSpacing
        let vSpacing = GridLayoutManager.verticalSpacing

        let itemsWidth = CGFloat(folderColumns) * itemWidth
        let spacingWidth = CGFloat(folderColumns - 1) * hSpacing
        let contentWidth = itemsWidth + spacingWidth + 48

        // FolderExpandedView 用 contentFrame 居中，gridOrigin 偏移 24px
        let contentFrameMinX = (lastGeometrySize.width - contentWidth) / 2
        let contentFrameMinY = (lastGeometrySize.height - 400) / 2
        let gridOrigin = CGPoint(
            x: contentFrameMinX + 24,
            y: contentFrameMinY + 82   // 非编辑模式偏移（编辑模式 108，取较小值覆盖更广）
        )

        let gridLayout = GridScreenLayout(
            frame: CGRect(origin: gridOrigin,
                          size: CGSize(width: contentWidth - 48, height: 400)),
            columns: folderColumns,
            itemWidth: itemWidth,
            itemHeight: itemHeight,
            horizontalSpacing: hSpacing,
            verticalSpacing: vSpacing
        )

        guard let rawIndex = gridLayout.rawIndex(at: location) else { return nil }
        guard rawIndex >= 0, rawIndex < folder.apps.count else { return nil }

        let center = gridLayout.itemCenter(at: rawIndex)
        let halfCellW = (itemWidth + hSpacing) / 2
        let halfCellH = (itemHeight + vSpacing) / 2
        if abs(location.x - center.x) <= halfCellW &&
           abs(location.y - center.y) <= halfCellH {
            return (folder.apps[rawIndex], rawIndex)
        }
        return nil
    }

    private func teardownEventManagers() {
        keyboardManager?.stopListening()
        gestureManager?.stopListening()
        keyboardManager = nil
        gestureManager = nil
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        let threshold: CGFloat = 50
        let velocity = value.predictedEndLocation.x - value.location.x
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if value.translation.width > threshold || velocity > 200 {
                paginationVM.previousPage()
            } else if value.translation.width < -threshold || velocity < -200 {
                paginationVM.nextPage(totalPages: totalPages)
            }
            dragAmount = .zero
        }
    }
    
    private func handleEscapeKey() {
        if editModeManager.isEditing {
            editModeManager.exitEditMode()
        } else if expandedFolder != nil {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                expandedFolder = nil
            }
        } else if !searchVM.searchText.isEmpty {
            searchVM.clearSearch()
        } else {
            hideWindow()
        }
    }
    
    private func hideWindow() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.hideMainWindow()
        } else {
            NSApplication.shared.keyWindow?.orderOut(nil)
        }
    }
    
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func resetLayout() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            expandedFolder = nil
        }
        clearFloatingDragState()
        dragAmount = .zero
        searchVM.clearSearch()
        paginationVM.reset()
        editModeManager.exitEditMode()
        launchpadVM.resetLayout()
    }

    private func clearFloatingDragState() {
        floatingDragState.clear()
    }
}

// MARK: - 通知扩展
extension Notification.Name {
    static let viewLayoutModeChanged = Notification.Name("viewLayoutModeChanged")
    /// 设置页（独立 ViewModel 实例）改了数据后发此通知，
    /// 主界面的 ViewModel 监听后 loadInstalledApps 刷新，避免设置页操作不同步到主界面。
    static let launchpadDataChanged = Notification.Name("launchpadDataChanged")
}

// MARK: - 可編輯的頁面視圖

struct PageViewEditable: View {
    let items: [LaunchpadDisplayItem]
    let layoutConfig: GridLayoutConfig
    let pageIndex: Int
    let currentPage: Int
    let screenWidth: CGFloat
    let dragAmount: CGSize
    let isEditing: Bool
    let draggingItemId: UUID?
    let dropTargetId: UUID?
    let onItemTap: (LaunchpadDisplayItem) -> Void
    let onLongPress: () -> Void
    let onDragChanged: (UUID, CGPoint) -> Void
    let onDragEnded: (UUID) -> Void
    
    var body: some View {
        VStack {
            // 減少頂部空間，讓 grid 更靠近搜尋欄
            Spacer().frame(minHeight: 0, maxHeight: 10)
            
            LazyVGrid(columns: layoutConfig.gridColumns, spacing: GridLayoutManager.verticalSpacing) {
                ForEach(items, id: \.id) { item in
                    LaunchpadItemView(
                        item: item,
                        onAppTap: { app in onItemTap(.app(app)) },
                        onFolderTap: { folder in onItemTap(.folder(folder)) },
                        isDragging: draggingItemId == item.id,
                        isEditing: isEditing,
                        isDropTarget: dropTargetId == item.id,
                        onLongPress: onLongPress,
                        onDragChanged: { location in
                            onDragChanged(item.id, location)
                        },
                        onDragEnded: {
                            onDragEnded(item.id)
                        }
                    )
                }
            }
            .frame(width: layoutConfig.gridWidth)
            
            // 減少底部空間
            Spacer().frame(minHeight: 0, maxHeight: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(
            x: CGFloat(pageIndex - currentPage) * screenWidth + dragAmount.width,
            y: 0
        )
        .opacity(pageIndex == currentPage ? 1.0 : 0.6)
        .scaleEffect(pageIndex == currentPage ? 1.0 : 0.92)
        // 在拖曳過程中，保持原頁面可以接收手勢
        .allowsHitTesting(pageIndex == currentPage || draggingItemId != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentPage)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
