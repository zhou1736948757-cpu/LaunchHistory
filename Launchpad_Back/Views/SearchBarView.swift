//
//  SearchBarView.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 2025/1/14.
//

import SwiftUI

/// 搜尋欄 UI 組件（類似原版 Launchpad）
struct SearchBarView: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    /// 滑块原始值，范围 0.0...1.0，默认 0.5（对应现默认大小 ratio 1.0）
    @AppStorage("searchBarSlider") var slider: Double = 0.5

    /// 实际渲染使用的比例（0.3...2.0）。
    /// 两段线性映射: slider 0.0→0.3, 0.5→1.0, 1.0→2.0
    private var sizeRatio: Double {
        if slider <= 0.5 {
            // [0, 0.5]: 0.3 + slider*1.4
            return 0.3 + slider * 1.4
        } else {
            // [0.5, 1.0]: 1.0 + (slider-0.5)*2
            return 1.0 + (slider - 0.5) * 2.0
        }
    }

    var body: some View {
        HStack(spacing: 10 * sizeRatio) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14 * sizeRatio, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            TextField("search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15 * sizeRatio))
                .foregroundStyle(.white)
                .focused($isFocused)
                .tint(.white)

            if !text.isEmpty {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        text = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14 * sizeRatio))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14 * sizeRatio)
        .padding(.vertical, 8 * sizeRatio)
        .frame(width: 240 * sizeRatio)
        .background(
            RoundedRectangle(cornerRadius: 10 * sizeRatio)
                .fill(.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 10 * sizeRatio)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

#if DEBUG
struct SearchBarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            SearchBarView(text: .constant(""))
        }
    }
}
#endif
