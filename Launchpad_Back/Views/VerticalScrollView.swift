//
//  VerticalScrollView.swift
//  Launchpad_Back
//
//  Created by CatPaw
//

import SwiftUI

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

                Spacer().frame(minHeight: 0, maxHeight: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}