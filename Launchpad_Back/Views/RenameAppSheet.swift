//
//  RenameAppSheet.swift
//  Launchpad_Back
//
//  Created on 2026-07-27.
//
//  应用重命名 sheet。
//  预填当前 displayName，空字符串表示恢复原始名称（由 renameApp 处理）。
//

import SwiftUI

/// 应用重命名 sheet。
///
/// - 预填 `app.displayName`（自訂名稱優先，否則原始名稱）。
/// - 提交空白字串時視為「恢復原名」，呼叫方會將 `nil`/空字串傳給 `renameApp`。
struct RenameAppSheet: View {
    let app: AppItem
    /// 完成回呼：傳入使用者輸入的新名稱（空字串 = 恢復原名）。
    let onCommit: (String) -> Void
    /// 取消回呼。
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var isFocused: Bool

    init(app: AppItem, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.app = app
        self.onCommit = onCommit
        self.onCancel = onCancel
        // 預填展示名稱（自訂名稱優先）；恢復原名時欄位清空即代表使用 originalName
        _name = State(initialValue: app.displayName)
    }

    var body: some View {
        VStack(spacing: 16) {
            // 標題
            Text("rename_title")
                .font(.headline)
                .foregroundStyle(.primary)

            // 應用圖示 + 原始名稱提示
            VStack(spacing: 6) {
                Text(app.originalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // 輸入欄
            TextField("rename_placeholder", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commit)

            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("rename_empty_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 按鈕列
            HStack(spacing: 12) {
                Button("cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("done") {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            // 進入時自動聚焦並全選，方便直接覆寫
            isFocused = true
        }
    }

    private func commit() {
        onCommit(name)
    }
}
