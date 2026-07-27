//
//  AppIconView.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 2025/1/14.
//

import SwiftUI
import AppKit

// MARK: - 抖動動畫修飾器

/// 編輯模式抖動效果
struct WiggleModifier: ViewModifier {
    let isWiggling: Bool
    @State private var wiggleAngle: Double = 0
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isWiggling ? wiggleAngle : 0))
            .onAppear {
                if isWiggling {
                    startWiggle()
                }
            }
            .onChange(of: isWiggling) { _, newValue in
                if newValue {
                    startWiggle()
                } else {
                    wiggleAngle = 0
                }
            }
    }
    
    private func startWiggle() {
        // 隨機化抖動，讓每個圖標抖動看起來不同步
        let randomDelay = Double.random(in: 0...0.1)
        let randomAmplitude = Double.random(in: 2.5...3.5)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + randomDelay) {
            withAnimation(
                .easeInOut(duration: 0.1)
                .repeatForever(autoreverses: true)
            ) {
                wiggleAngle = randomAmplitude
            }
        }
    }
}

extension View {
    func wiggle(_ isWiggling: Bool) -> some View {
        modifier(WiggleModifier(isWiggling: isWiggling))
    }
}

struct CachedAppIconImage<Placeholder: View>: View {
    let path: String
    let appName: String?
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var icon: NSImage?
    @State private var requestedID = ""
    
    private var taskID: String {
        "\(path)\u{0}\(appName ?? "")"
    }
    
    var body: some View {
        Group {
            if let icon, icon.size.width > 0 {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder()
            }
        }
        .task(id: taskID) {
            loadIcon()
        }
        .onDisappear {
            requestedID = ""
            icon = nil
        }
    }
    
    private func loadIcon() {
        requestedID = taskID
        
        if let cachedIcon = AppIconCache.shared.cachedIcon(for: path) {
            icon = cachedIcon
            return
        }
        
        icon = nil
        AppIconCache.shared.getIconAsync(for: path, appName: appName) { loadedIcon in
            guard requestedID == taskID else { return }
            icon = loadedIcon
        }
    }
}

struct IconLoadingPlaceholder: View {
    var cornerRadius: CGFloat = 18
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.06)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - 共用的交互式圖標容器（消除重複代碼）

/// 交互式圖標配置
struct InteractiveIconConfig {
    let name: String
    let isDragging: Bool
    let isEditing: Bool
    let isDropTarget: Bool
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    let onDragChanged: ((CGPoint) -> Void)?
    let onDragEnded: (() -> Void)?
}

/// 交互式圖標容器 ViewModifier - 提取共用邏輯
struct InteractiveIconModifier: ViewModifier {
    let config: InteractiveIconConfig

    @State private var dragOffset: CGSize = .zero
    @State private var didTriggerLongPressDrag = false

    func body(content: Content) -> some View {
        content
            .wiggle(config.isEditing && !config.isDragging)
            .opacity(config.isDragging ? 0.3 : 1.0)
            .overlay(dropTargetOverlay)
            .offset(dragOffset)
            .contentShape(Rectangle())
            // 恢复基线手势组合（8cf98a7 验证可用）：
            // - editDragGesture 用 highPriorityGesture，确保编辑模式拖动优先
            // - tap 和 longPress 用 simultaneousGesture，纯点击打开应用，
            //   长按 0.2s 进编辑模式（不依赖 didLongPress 状态抑制 tap）
            .highPriorityGesture(editDragGesture, including: .gesture)
            .simultaneousGesture(tapGesture)
            .simultaneousGesture(longPressInteractionGesture)
    }

    // MARK: - 手势

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                config.onTap()
            }
    }

    /// 按住 0.2s 进入抖动编辑模式（HyperOS 风格：长按后不松手即可拖动）
    private var longPressInteractionGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if !didTriggerLongPressDrag {
                        // 首次拖动：若尚未处于编辑模式，触发进入编辑模式（所有图标开始抖动）
                        if !config.isEditing {
                            Logger.info("Long press detected on \(config.name)")
                            config.onLongPress?()
                        }
                        didTriggerLongPressDrag = true
                    }
                    // 即便 isEditing 已因 enterEditMode() 翻转为 true，仍持续追踪拖动
                    dragOffset = drag.translation
                    config.onDragChanged?(drag.location)
                default:
                    break
                }
            }
            .onEnded { value in
                var didDrag = false
                switch value {
                case .second(true, let drag?):
                    didDrag = true
                    dragOffset = drag.translation
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                    config.onDragEnded?()
                default:
                    break
                }

                // 长按识别后若没有拖动，且尚未进入编辑模式，则进入编辑模式
                if !didDrag, !didTriggerLongPressDrag, !config.isEditing {
                    Logger.info("Long press detected on \(config.name)")
                    config.onLongPress?()
                }

                didTriggerLongPressDrag = false
            }
    }

    /// 编辑模式下的快速拖动（移动超过 5pt 即触发）。
    private var editDragGesture: some Gesture {
        DragGesture(minimumDistance: config.isEditing ? 5 : 1000, coordinateSpace: .global)
            .onChanged { value in
                guard config.isEditing else { return }
                dragOffset = value.translation
                config.onDragChanged?(value.location)
            }
            .onEnded { _ in
                guard config.isEditing else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragOffset = .zero
                }
                config.onDragEnded?()
            }
    }
    
    // MARK: - UI 組件
    
    @ViewBuilder
    private var dropTargetOverlay: some View {
        if config.isDropTarget {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.6), lineWidth: 3)
                .frame(width: GridLayoutManager.iconSize + 10, height: GridLayoutManager.iconSize + 10)
                .offset(y: -8)
        }
    }
}

/// 計算縮放值的工具函數
func calculateScaleValue(isDropTarget: Bool, isDragging: Bool, isHovered: Bool) -> CGFloat {
    if isDropTarget {
        return 1.2
    } else if isDragging {
        return 1.1
    } else if isHovered {
        return 1.08
    }
    return 1.0
}

// MARK: - 圖標圖片容器

/// 共用的圖標圖片視圖（帶動畫和陰影）
struct IconImageContainer<Content: View>: View {
    let isDropTarget: Bool
    let isDragging: Bool
    @ViewBuilder let content: () -> Content
    
    @State private var isHovered = false
    
    var body: some View {
        content()
            .frame(width: GridLayoutManager.iconSize, height: GridLayoutManager.iconSize)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.2), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
            .scaleEffect(calculateScaleValue(isDropTarget: isDropTarget, isDragging: isDragging, isHovered: isHovered))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDropTarget)
            .onHover { isHovered = $0 }
    }
}

/// 圖標標籤視圖
struct IconLabelView: View {
    let name: String
    
    var body: some View {
        Text(name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(width: GridLayoutManager.labelMaxWidth, height: GridLayoutManager.labelHeight, alignment: .top)
    }
}

// MARK: - 單個應用程式圖示視圖

/// 單個應用程式圖示視圖
struct AppIconView: View {
    let app: AppItem
    let onTap: () -> Void
    var isDragging: Bool = false
    var isEditing: Bool = false
    var isDropTarget: Bool = false
    var onLongPress: (() -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onToggleHide: ((AppItem) -> Void)?
    var onShowInFinder: ((AppItem) -> Void)?
    var onGetInfo: ((AppItem) -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            // 圖示
            IconImageContainer(isDropTarget: isDropTarget, isDragging: isDragging) {
                CachedAppIconImage(path: app.path, appName: app.name) {
                    defaultIconView
                }
            }

            // 應用程式名稱（可由設置面板控制是否顯示）
            if GridLayoutManager.showIconLabels {
                IconLabelView(name: app.name)
            }
        }
        .modifier(InteractiveIconModifier(config: InteractiveIconConfig(
            name: app.name,
            isDragging: isDragging,
            isEditing: isEditing,
            isDropTarget: isDropTarget,
            onTap: onTap,
            onLongPress: onLongPress,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )))
        .contextMenu {
            appContextMenu
        }
    }
    
    private var defaultIconView: some View {
        IconLoadingPlaceholder(cornerRadius: 18)
    }

    @ViewBuilder
    private var appContextMenu: some View {
        // 應用程式操作
        Button(action: { onShowInFinder?(app) }) {
            Label("show_in_finder", systemImage: "folder")
        }

        Button(action: { onGetInfo?(app) }) {
            Label("get_info", systemImage: "info.circle")
        }

        Divider()

        // 顯示/隱藏選項
        Button(action: { onToggleHide?(app) }) {
            Label(app.isHidden ? LocalizedStringKey("show_in_launchpad") : LocalizedStringKey("hide_from_launchpad"), systemImage: app.isHidden ? "eye" : "eye.slash")
        }

        Divider()

        // 編輯模式相關
        if !isEditing {
            Button(action: { onLongPress?() }) {
                Label("enter_edit_mode", systemImage: "pencil.circle")
            }
        } else {
            Label("in_edit_mode", systemImage: "checkmark.circle")
                .disabled(true)
        }
    }
}

/// 文件夾圖示視圖
struct FolderIconView: View {
    let folder: AppFolder
    let onTap: () -> Void
    var isDragging: Bool = false
    var isEditing: Bool = false
    var isDropTarget: Bool = false
    var onLongPress: (() -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onRenameFolder: ((AppFolder) -> Void)?
    var onDeleteFolder: ((AppFolder) -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            // 文件夾圖示（3x3 網格預覽）
            IconImageContainer(isDropTarget: isDropTarget, isDragging: isDragging) {
                folderIconGrid
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                    )
            }

            // 文件夾名稱（可由設置面板控制是否顯示）
            if GridLayoutManager.showIconLabels {
                IconLabelView(name: folder.name)
            }
        }
        .modifier(InteractiveIconModifier(config: InteractiveIconConfig(
            name: folder.name,
            isDragging: isDragging,
            isEditing: isEditing,
            isDropTarget: isDropTarget,
            onTap: onTap,
            onLongPress: onLongPress,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )))
        .contextMenu {
            folderContextMenu
        }
    }
    
    private var folderIconGrid: some View {
        let iconSize: CGFloat = 22
        let spacing: CGFloat = 4
        let padding: CGFloat = 8
        
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(iconSize), spacing: spacing), count: 3),
            spacing: spacing
        ) {
            ForEach(0..<9, id: \.self) { index in
                if index < folder.apps.count {
                    CachedAppIconImage(path: folder.apps[index].path, appName: folder.apps[index].name) {
                        emptySlot(size: iconSize)
                    }
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    emptySlot(size: iconSize)
                }
            }
        }
        .padding(padding)
    }
    
    private func emptySlot(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.clear)
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var folderContextMenu: some View {
        // 文件夾信息
        Text("folder_contains_apps \(folder.apps.count)")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        // 文件夾操作
        Button(action: { onRenameFolder?(folder) }) {
            Label("rename", systemImage: "pencil")
        }

        if !isEditing {
            Button(action: { onDeleteFolder?(folder) }) {
                Label("delete_folder", systemImage: "trash")
            }
        } else {
            Label("in_edit_mode", systemImage: "checkmark.circle")
                .disabled(true)
        }

        Divider()

        // 編輯模式相關
        if !isEditing {
            Button(action: { onLongPress?() }) {
                Label("enter_edit_mode", systemImage: "pencil.circle")
            }
        }
    }
}

/// Launchpad 項目視圖（支持應用和文件夾）
struct LaunchpadItemView: View {
    let item: LaunchpadDisplayItem
    let onAppTap: (AppItem) -> Void
    let onFolderTap: (AppFolder) -> Void
    var isDragging: Bool = false
    var isEditing: Bool = false
    var isDropTarget: Bool = false
    var onLongPress: (() -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onToggleHide: ((AppItem) -> Void)?
    var onShowInFinder: ((AppItem) -> Void)?
    var onGetInfo: ((AppItem) -> Void)?
    var onRenameFolder: ((AppFolder) -> Void)?
    var onDeleteFolder: ((AppFolder) -> Void)?
    
    var body: some View {
        switch item {
        case .app(let app):
            AppIconView(
                app: app,
                onTap: { onAppTap(app) },
                isDragging: isDragging,
                isEditing: isEditing,
                isDropTarget: isDropTarget,
                onLongPress: onLongPress,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                onToggleHide: onToggleHide,
                onShowInFinder: onShowInFinder,
                onGetInfo: onGetInfo
            )
        case .folder(let folder):
            FolderIconView(
                folder: folder,
                onTap: { onFolderTap(folder) },
                isDragging: isDragging,
                isEditing: isEditing,
                isDropTarget: isDropTarget,
                onLongPress: onLongPress,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                onRenameFolder: onRenameFolder,
                onDeleteFolder: onDeleteFolder
            )
        }
    }
}

#if DEBUG
struct AppIconView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleApp = AppItem(name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app", isSystemApp: false)
        return AppIconView(app: sampleApp) {}
    }
}
#endif
