//
//  SettingsView.swift
//  Launch_historyreview
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 通知扩展（热区设置变化）

extension Notification.Name {
    /// 热区启用角落集合变化时派发，object 为 Set<HotCorner>
    static let hotCornerSettingsChanged = Notification.Name("hotCornerSettingsChanged")
}

// MARK: - 标签枚举

enum SettingsTab: CaseIterable {
    case general, appearance, gesture, hotkey, about

    var title: LocalizedStringKey {
        switch self {
        case .general:    return "tab_general"
        case .appearance: return "tab_appearance"
        case .gesture:    return "tab_gesture"
        case .hotkey:     return "tab_hotkey"
        case .about:      return "tab_about"
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
    @StateObject private var launchpadVM = LaunchpadViewModel()
    @AppStorage("windowMode")       private var windowMode:        WindowMode = .fullscreen
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double    = 0.85
    @AppStorage("blurEnabled")      private var blurEnabled:       Bool       = true
    @AppStorage("languagePreference") private var languagePreferenceRaw: String = LanguagePreference.system.rawValue

    var body: some View {
        Form {
            Section("section_window") {
                Picker("window_mode", selection: $windowMode) {
                    ForEach(WindowMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .onChange(of: windowMode) { _, _ in
                    NotificationCenter.default.post(name: .windowModeChanged, object: nil)
                }

                Toggle("blur_enabled", isOn: $blurEnabled)

                Slider(value: $backgroundOpacity, in: 0.0...1.0) {
                    Text("background_opacity")
                } minimumValueLabel: {
                    Text("transparent").font(.caption)
                } maximumValueLabel: {
                    Text("opaque").font(.caption)
                }
            }

            Section("section_refresh_rate") {
                Picker("refresh_rate", selection: binding(\.refreshRate)) {
                    ForEach(RefreshRate.allCases, id: \.self) { rate in
                        Text(rate.localizedName).tag(rate)
                    }
                }
                .onChange(of: pm.preferences.refreshRate) { _, newValue in
                    let mode: RefreshRateMode = (newValue == .high || newValue == .ultra) ? .hz120 : .hz60
                    DisplayManager.shared.setRefreshRate(mode)
                }
            }

            Section("section_advanced") {
                Toggle("auto_launch_at_login", isOn: binding(\.autoLaunchAtLogin))
                Toggle("check_for_updates",     isOn: binding(\.checkForUpdates))
                Toggle("debug_mode",     isOn: binding(\.debugModeEnabled))
            }

            Section("section_language") {
                Picker("language", selection: $languagePreferenceRaw) {
                    ForEach(LanguagePreference.allCases, id: \.self.rawValue) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .onChange(of: languagePreferenceRaw) { _, newValue in
                    let pref = LanguagePreference(rawValue: newValue) ?? .system
                    LocalizationManager.shared.applyPreference(pref)
                }

                // 选手动语言时显示重启提示；选“跟随系统”时不显示
                if LocalizationManager.shared.needsRestart {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                        Text("restart_required")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("quit_and_reopen") {
                        quitAndReopen()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("quit_and_reopen_help")
                }
            }

            // 自訂 App 來源
            Section("section_app_sources") {
                Button("add_app_source") {
                    showAddAppSourcePanel()
                }
                customAppSourcesList
            }

            // 已隱藏應用
            Section("section_hidden_apps") {
                hiddenAppsList
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchpadVM.loadInstalledApps()
        }
    }

    /// 自訂 App 來源列表。空時顯示提示。
    @ViewBuilder
    private var customAppSourcesList: some View {
        let paths = launchpadVM.customAppPaths
        if paths.isEmpty {
            Text("no_custom_app_sources")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(paths.enumerated()), id: \.element) { _, url in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.body)
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        launchpadVM.removeCustomAppPath(url)
                    } label: {
                        Text("remove")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    /// 已隱藏應用列表。空時顯示提示。
    @ViewBuilder
    private var hiddenAppsList: some View {
        let entries = launchpadVM.hiddenAppEntries
        if entries.isEmpty {
            Text("no_hidden_apps")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.body)
                        if let path = entry.path {
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Button("show_app") {
                        showHiddenApp(entry)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func binding<T>(_ kp: WritableKeyPath<UserPreferences, T>) -> Binding<T> {
        Binding(get: { pm.preferences[keyPath: kp] },
                set: { pm.update(keyPath: kp, value: $0) })
    }

    /// 弹出 NSOpenPanel 让用户选择一个 .app 加入自定义来源。
    /// 重复不添加（addCustomAppPath 内部已去重）。
    private func showAddAppSourcePanel() {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("add_app_source", comment: "")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        // 只接受 .app 后缀
        guard url.pathExtension == "app" else {
            Logger.warning("Selected URL is not an .app: \(url.path)")
            return
        }

        launchpadVM.addCustomAppPath(url)
    }

    /// 恢复被隐藏的应用。
    /// 通过 stableIdentifier 在 allApps 中反查 AppItem 后调用 toggleAppVisibility。
    private func showHiddenApp(_ entry: HiddenAppEntry) {
        guard let app = launchpadVM.allApps.first(where: { $0.stableIdentifier == entry.id }) else {
            Logger.warning("Cannot restore hidden app: no matching AppItem for \(entry.id)")
            return
        }
        launchpadVM.toggleAppVisibility(app)
    }

    /// 退出并重新打开应用（语言切换后需要新实例才能生效）。
    /// 待验收：若 /usr/bin/open -n 无法稳定启动新实例，可改为通过 launchd/registration
    /// 或独立 launcher helper 实现。第一版先按此实现。
    private func quitAndReopen() {
        guard let appURL = NSRunningApplication.current.bundleURL else {
            Logger.error("Cannot resolve current app bundle URL to restart")
            return
        }

        Logger.info("Quit-and-reopen requested; relaunching \(appURL.path)")
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", appURL.path]
        do {
            try task.run()
        } catch {
            Logger.error("Failed to relaunch app: \(error.localizedDescription)")
            return
        }

        // 留时间让 open -n 把新实例拉起，再终止当前实例
        // 0.3s：比 0.1s 更稳，避免新实例启动慢时出现无窗口间隙
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - 外观设置

struct AppearanceSettingsView: View {
    @AppStorage("iconSize")           private var iconSize:           Double = 80
    @AppStorage("gridColumns")        private var gridColumns:        Int    = 7
    @AppStorage("showIconLabels")     private var showIconLabels:     Bool   = true
    @AppStorage("searchBarSlider")    private var searchBarSlider:    Double = 0.5
    @AppStorage("viewLayoutMode")     private var viewLayoutMode:      ViewLayoutMode = .horizontalPaging

    var body: some View {
        Form {
            Section("section_icon") {
                Slider(value: $iconSize, in: 48...110, step: 2) {
                    Text("icon_size")
                } minimumValueLabel: {
                    Text("size_small").font(.caption)
                } maximumValueLabel: {
                    Text("size_large").font(.caption)
                }
                .onChange(of: iconSize) { _, _ in postLayoutChanged() }

                Text("current_value_pt \(Int(iconSize))")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("show_icon_labels", isOn: $showIconLabels)
                    .onChange(of: showIconLabels) { _, _ in postLayoutChanged() }

                Stepper(value: $gridColumns, in: 4...9) {
                    Text("icons_per_row \(gridColumns)")
                }
                .onChange(of: gridColumns) { _, _ in postLayoutChanged() }
            }

            Section("section_layout") {
                Picker("layout_mode", selection: $viewLayoutMode) {
                    ForEach(ViewLayoutMode.allCases, id: \.self) { mode in
                        Text(layoutModeTitle(mode)).tag(mode)
                    }
                }
                .onChange(of: viewLayoutMode) { _, newValue in
                    NotificationCenter.default.post(name: .viewLayoutModeChanged, object: newValue)
                    // 触发布局重建以应用新布局
                    postLayoutChanged()
                }
            }

            Section("section_search_bar") {
                Slider(value: $searchBarSlider, in: 0.0...1.0, step: 0.05) {
                    Text("search_bar_size")
                } minimumValueLabel: {
                    Text("size_small").font(.caption)
                } maximumValueLabel: {
                    Text("size_large").font(.caption)
                }

                Text("current_size_percent \(Int(searchBarSlider * 100))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func postLayoutChanged() {
        NotificationCenter.default.post(name: .layoutSettingsChanged, object: nil)
    }

    /// 布局模式对应的本地化标题。
    private func layoutModeTitle(_ mode: ViewLayoutMode) -> LocalizedStringKey {
        switch mode {
        case .horizontalPaging: return "horizontal_paging"
        case .verticalScroll:   return "vertical_scroll"
        }
    }
}

// MARK: - 手势设置（简化版）

struct GestureSettingsView: View {
    @ObservedObject private var pm = UserPreferencesManager.shared
    @State private var hasAccessibility: Bool = AXIsProcessTrusted()

    // 热区（触发角）开关，与 AppDelegate 共享同一组 UserDefaults key。
    @AppStorage("hotCornerTopLeft")     private var hotCornerTopLeft:     Bool = false
    @AppStorage("hotCornerTopRight")    private var hotCornerTopRight:    Bool = false
    @AppStorage("hotCornerBottomLeft")  private var hotCornerBottomLeft:  Bool = false
    @AppStorage("hotCornerBottomRight") private var hotCornerBottomRight: Bool = false

    var body: some View {
        Form {
            // 辅助功能权限状态
            Section("section_accessibility") {
                HStack {
                    Image(systemName: hasAccessibility ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(hasAccessibility ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasAccessibility ? LocalizedStringKey("permission_granted") : LocalizedStringKey("accessibility_permission_required"))
                            .font(.body)
                        Text(hasAccessibility
                             ? LocalizedStringKey("gesture_available")
                             : LocalizedStringKey("gesture_needs_permission"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !hasAccessibility {
                        Button("go_to_authorize") {
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
            Section("section_gesture_switch") {
                Toggle("enable_gesture_wake", isOn: binding(\.gesturesEnabled))
                    .onChange(of: pm.preferences.gesturesEnabled) { _, _ in
                        NotificationCenter.default.post(name: .gesturesChanged, object: nil)
                    }
            }

            // 热区（触发角）
            Section("section_hot_corner") {
                Toggle(HotCorner.topLeft.localizedName,     isOn: $hotCornerTopLeft)
                    .onChange(of: hotCornerTopLeft) { _, _ in notifyHotCornerChanged() }
                Toggle(HotCorner.topRight.localizedName,    isOn: $hotCornerTopRight)
                    .onChange(of: hotCornerTopRight) { _, _ in notifyHotCornerChanged() }
                Toggle(HotCorner.bottomLeft.localizedName,  isOn: $hotCornerBottomLeft)
                    .onChange(of: hotCornerBottomLeft) { _, _ in notifyHotCornerChanged() }
                Toggle(HotCorner.bottomRight.localizedName, isOn: $hotCornerBottomRight)
                    .onChange(of: hotCornerBottomRight) { _, _ in notifyHotCornerChanged() }
            }

            // 固定手势操作说明
            Section("section_gesture_actions") {
                LabeledContent("open_panel") {
                    Label("four_finger_pinch", systemImage: "hand.draw.fill")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("close_panel") {
                    HStack(spacing: 4) {
                        Label("four_finger_spread", systemImage: "arrow.up.left.and.arrow.down.right")
                        Text("/")
                            .foregroundStyle(.tertiary)
                        Label("tap_blank", systemImage: "cursorarrow.click")
                    }
                    .foregroundStyle(.secondary)
                }
                LabeledContent("hotkey") {
                    Text("⌘ + L")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("hot_corner_open") {
                    Label("mouse_hover_corner", systemImage: "rectangle.dashed.and.paperclip")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// 根据四个 Toggle 当前状态计算启用的角落集合，并通知 AppDelegate 更新 HotCornerMonitor。
    private func notifyHotCornerChanged() {
        var enabled: Set<HotCorner> = []
        if hotCornerTopLeft     { enabled.insert(.topLeft) }
        if hotCornerTopRight    { enabled.insert(.topRight) }
        if hotCornerBottomLeft  { enabled.insert(.bottomLeft) }
        if hotCornerBottomRight { enabled.insert(.bottomRight) }
        NotificationCenter.default.post(name: .hotCornerSettingsChanged, object: enabled)
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
            Section("section_app_info") {
                LabeledContent("name",    value: "Launch_historyreview")
                LabeledContent("version",    value: "0.4")
                LabeledContent("license", value: "GPL-3.0")
                // 项目地址暂留空，待上传 GitHub 后填写
            }

            Section("section_settings_management") {
                Button("restore_defaults", role: .destructive) {
                    pm.resetToDefaults()
                }
                Button("clear_all_settings") {
                    pm.clearAllSettings()
                }
            }
        }
        .formStyle(.grouped)
    }
}
