//
//  SettingsView.swift
//  Launch_historyreview
//

import SwiftUI

// MARK: - 标签枚举

enum SettingsTab: CaseIterable {
    case general, appearance, gesture, hotkey, about

    var title: String {
        switch self {
        case .general:    return "通用"
        case .appearance: return "外观"
        case .gesture:    return "手势"
        case .hotkey:     return "快捷键"
        case .about:      return "关于"
        }
    }
}

// MARK: - 设置面板主视图

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶部自定义导航栏 ──────────────────────
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.55))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(.white.opacity(0.18))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            Divider().opacity(0.3)

            // ── 内容区 ────────────────────────────────
            Group {
                switch selectedTab {
                case .general:    GeneralSettingsView()
                case .appearance: AppearanceSettingsView()
                case .gesture:    GestureSettingsView()
                case .hotkey:     HotkeySettingsView()
                case .about:      AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 680, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - 通用设置

struct GeneralSettingsView: View {
    @ObservedObject private var pm = UserPreferencesManager.shared
    @AppStorage("windowMode")       private var windowMode:        WindowMode = .fullscreen
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double    = 0.85
    @AppStorage("blurEnabled")      private var blurEnabled:       Bool       = true

    var body: some View {
        Form {
            Section("窗口") {
                Picker("窗口模式", selection: $windowMode) {
                    ForEach(WindowMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .onChange(of: windowMode) { _, _ in
                    NotificationCenter.default.post(name: .windowModeChanged, object: nil)
                }

                Toggle("启用模糊效果", isOn: $blurEnabled)

                Slider(value: $backgroundOpacity, in: 0.0...1.0) {
                    Text("背景不透明度")
                } minimumValueLabel: {
                    Text("透明").font(.caption)
                } maximumValueLabel: {
                    Text("不透明").font(.caption)
                }
            }

            Section("刷新率") {
                Picker("刷新率", selection: binding(\.refreshRate)) {
                    ForEach(RefreshRate.allCases, id: \.self) { rate in
                        Text(rate.localizedName).tag(rate)
                    }
                }
                .onChange(of: pm.preferences.refreshRate) { _, newValue in
                    let mode: RefreshRateMode = (newValue == .high || newValue == .ultra) ? .hz120 : .hz60
                    DisplayManager.shared.setRefreshRate(mode)
                }
            }

            Section("高级") {
                Toggle("开机自动启动", isOn: binding(\.autoLaunchAtLogin))
                Toggle("检查更新",     isOn: binding(\.checkForUpdates))
                Toggle("调试模式",     isOn: binding(\.debugModeEnabled))
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ kp: WritableKeyPath<UserPreferences, T>) -> Binding<T> {
        Binding(get: { pm.preferences[keyPath: kp] },
                set: { pm.update(keyPath: kp, value: $0) })
    }
}

// MARK: - 外观设置

struct AppearanceSettingsView: View {
    @AppStorage("iconSize")           private var iconSize:           Double = 80
    @AppStorage("gridColumns")        private var gridColumns:        Int    = 7
    @AppStorage("showIconLabels")     private var showIconLabels:     Bool   = true
    @AppStorage("searchBarSizeRatio") private var searchBarSizeRatio: Double = 0.6

    var body: some View {
        Form {
            Section("图标") {
                Slider(value: $iconSize, in: 48...110, step: 2) {
                    Text("图标大小")
                } minimumValueLabel: {
                    Text("小").font(.caption)
                } maximumValueLabel: {
                    Text("大").font(.caption)
                }
                .onChange(of: iconSize) { _, _ in postLayoutChanged() }

                Text("当前：\(Int(iconSize)) pt")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("显示图标名称", isOn: $showIconLabels)
                    .onChange(of: showIconLabels) { _, _ in postLayoutChanged() }

                Stepper(value: $gridColumns, in: 4...9) {
                    Text("每行图标数：\(gridColumns)")
                }
                .onChange(of: gridColumns) { _, _ in postLayoutChanged() }
            }

            Section("搜索栏") {
                Slider(value: $searchBarSizeRatio, in: 0.4...1.0, step: 0.05) {
                    Text("搜索栏大小")
                } minimumValueLabel: {
                    Text("小").font(.caption)
                } maximumValueLabel: {
                    Text("大").font(.caption)
                }

                Text("当前大小：\(Int(searchBarSizeRatio * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func postLayoutChanged() {
        NotificationCenter.default.post(name: .layoutSettingsChanged, object: nil)
    }
}

// MARK: - 手势设置（简化版）

struct GestureSettingsView: View {
    @ObservedObject private var pm = UserPreferencesManager.shared
    @State private var hasAccessibility: Bool = AXIsProcessTrusted()

    var body: some View {
        Form {
            // 辅助功能权限状态
            Section("辅助功能权限") {
                HStack {
                    Image(systemName: hasAccessibility ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(hasAccessibility ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasAccessibility ? "权限已授予" : "需要辅助功能权限")
                            .font(.body)
                        Text(hasAccessibility
                             ? "手势唤醒功能已可用"
                             : "手势唤醒（面板隐藏时）需要此权限")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !hasAccessibility {
                        Button("前往授权") {
                            openAccessibilitySettings()
                            // 延迟刷新状态
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                hasAccessibility = AXIsProcessTrusted()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .onAppear { hasAccessibility = AXIsProcessTrusted() }
            }

            // 手势开关
            Section("手势开关") {
                Toggle("启用手势唤醒", isOn: binding(\.gesturesEnabled))
                    .onChange(of: pm.preferences.gesturesEnabled) { _, _ in
                        NotificationCenter.default.post(name: .gesturesChanged, object: nil)
                    }
            }

            // 固定手势操作说明
            Section("手势操作") {
                LabeledContent("打开面板") {
                    Label("四指捏拢", systemImage: "hand.draw.fill")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("关闭面板") {
                    HStack(spacing: 4) {
                        Label("四指张开", systemImage: "arrow.up.left.and.arrow.down.right")
                        Text("/")
                            .foregroundStyle(.tertiary)
                        Label("点击空白", systemImage: "cursorarrow.click")
                    }
                    .foregroundStyle(.secondary)
                }
                LabeledContent("快捷键") {
                    Text("⌘ + L")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func binding<T>(_ kp: WritableKeyPath<UserPreferences, T>) -> Binding<T> {
        Binding(get: { pm.preferences[keyPath: kp] },
                set: { pm.update(keyPath: kp, value: $0) })
    }
}

// MARK: - 关于

struct AboutView: View {
    @ObservedObject private var pm = UserPreferencesManager.shared

    var body: some View {
        Form {
            Section("应用信息") {
                LabeledContent("名称",    value: "Launch_historyreview")
                LabeledContent("版本",    value: "0.4")
                LabeledContent("授权协议", value: "GPL-3.0")
                // 项目地址暂留空，待上传 GitHub 后填写
            }

            Section("设置管理") {
                Button("恢复默认设置", role: .destructive) {
                    pm.resetToDefaults()
                }
                Button("清除所有设置") {
                    pm.clearAllSettings()
                }
            }
        }
        .formStyle(.grouped)
    }
}
