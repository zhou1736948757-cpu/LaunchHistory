//
//  VerticalScrollView.swift
//  Launchpad_Back
//
//  Created by CatPaw
//

import SwiftUI

/// 追踪垂直滚动网格在全局坐标空间中的 frame（随滚动变化）
/// ContentView 用它来计算拖放落点目标
struct VerticalGridFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct VerticalScrollView: View {
    let items: [LaunchpadDisplayItem]
    let layoutConfig: GridLayoutConfig
    let isEditing: Bool
    let draggingItemId: UUID?
    let dropTargetId: UUID?
    let onItemTap: (LaunchpadDisplayItem) -> Void
    let onLongPress: () -> Void
    let onDragChanged: (UUID, CGPoint) -> Void
    let onDragEnded: (UUID) -> Void
    /// 网格在全局坐标空间中 frame 的回调（随滚动更新）
    var onGridFrameChanged: ((CGRect) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                // 追踪网格在全局坐标中的 frame（包含因滚动产生的位移）
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: VerticalGridFramePreferenceKey.self,
                                value: proxy.frame(in: .global)
                            )
                    }
                )

                Spacer().frame(minHeight: 0, maxHeight: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        // 编辑模式下禁用 ScrollView 滚动，避免单指拖动图标时被 ScrollView 抢走手势
        .scrollDisabled(isEditing)
        .onPreferenceChange(VerticalGridFramePreferenceKey.self) { frame in
            onGridFrameChanged?(frame)
        }
    }
}
