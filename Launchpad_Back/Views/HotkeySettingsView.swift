//
//  HotkeySettingsView.swift
//  Launchpad_Back
//
//  Created on 2026-07-25.
//

import SwiftUI

/// 快捷键类型
enum HotkeyType: String, CaseIterable {
    case toggleWindow = "toggleWindow"
    case previousPage = "previousPage"
    case nextPage = "nextPage"
    case hideWindow = "hideWindow"
    case quitApp = "quitApp"

    var displayName: String {
        switch self {
        case .toggleWindow: return "显示/隐藏窗口"
        case .previousPage: return "上一页"
        case .nextPage: return "下一页"
        case .hideWindow: return "隐藏窗口"
        case .quitApp: return "退出应用"
        }
    }
}

/// 快捷键设置视图
struct HotkeySettingsView: View {
    @AppStorage("hotkeyToggle") private var toggleHotkey = "⌘L"
    @AppStorage("hotkeyPrevious") private var previousHotkey = "←"
    @AppStorage("hotkeyNext") private var nextHotkey = "→"
    @AppStorage("hotkeyHide") private var hideHotkey = "⌘W"
    @AppStorage("hotkeyQuit") private var quitHotkey = "⌘Q"

    @State private var recordingHotkey: HotkeyType?
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        Form {
            Section(header: Text("全局快捷键")) {
                HotkeyRow(
                    title: "显示/隐藏窗口",
                    hotkey: toggleHotkey,
                    isRecording: recordingHotkey == .toggleWindow,
                    onTap: { startRecording(.toggleWindow) }
                )

                HotkeyRow(
                    title: "上一页",
                    hotkey: previousHotkey,
                    isRecording: recordingHotkey == .previousPage,
                    onTap: { startRecording(.previousPage) }
                )

                HotkeyRow(
                    title: "下一页",
                    hotkey: nextHotkey,
                    isRecording: recordingHotkey == .nextPage,
                    onTap: { startRecording(.nextPage) }
                )

                HotkeyRow(
                    title: "隐藏窗口",
                    hotkey: hideHotkey,
                    isRecording: recordingHotkey == .hideWindow,
                    onTap: { startRecording(.hideWindow) }
                )

                HotkeyRow(
                    title: "退出应用",
                    hotkey: quitHotkey,
                    isRecording: recordingHotkey == .quitApp,
                    onTap: { startRecording(.quitApp) }
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("快捷键")
        .alert("快捷键设置", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - 录制逻辑

    private func startRecording(_ type: HotkeyType) {
        recordingHotkey = type
        Logger.info("开始录制快捷键: \(type.displayName)")

        // 监听键盘事件
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard let recordingHotkey = self.recordingHotkey,
                  event.keyCode != 0x35 else {  // 排除 Escape 键
                return event
            }

            let hotkeyString = formatHotkeyString(event)

            // 更新对应的热键
            switch recordingHotkey {
            case .toggleWindow:
                toggleHotkey = hotkeyString
            case .previousPage:
                previousHotkey = hotkeyString
            case .nextPage:
                nextHotkey = hotkeyString
            case .hideWindow:
                hideHotkey = hotkeyString
            case .quitApp:
                quitHotkey = hotkeyString
            }

            Logger.info("录制快捷键: \(hotkeyString)")

            // 停止录制
            self.recordingHotkey = nil

            return nil // 阻止事件传递
        }
    }

    private func stopRecording() {
        recordingHotkey = nil
    }

    private func formatHotkeyString(_ event: NSEvent) -> String {
        var result = ""

        if event.modifierFlags.contains(.command) {
            result += "⌘"
        }
        if event.modifierFlags.contains(.option) {
            result += "⌥"
        }
        if event.modifierFlags.contains(.control) {
            result += "⌃"
        }
        if event.modifierFlags.contains(.shift) {
            result += "⇧"
        }

        // 添加键名
        if let keyName = keyName(for: event.keyCode) {
            result += keyName
        }

        return result
    }

    private func keyName(for keyCode: UInt16) -> String? {
        let keyNames: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0A: "B", 0x0B: "Q", 0x0C: "W", 0x0D: "E", 0x0E: "R",
            0x0F: "Y", 0x10: "T", 0x11: "1", 0x12: "2", 0x13: "3",
            0x14: "4", 0x15: "6", 0x16: "5", 0x17: "=", 0x18: "9",
            0x19: "7", 0x1A: "-", 0x1B: "8", 0x1C: "0", 0x1D: "]",
            0x1E: "O", 0x1F: "U", 0x20: "[", 0x21: "I", 0x22: "P",
            0x23: "L", 0x24: "J", 0x25: "'", 0x26: "K", 0x27: ";",
            0x28: "\\", 0x29: ",", 0x2A: "/", 0x2B: "N", 0x2C: "M",
            0x2D: ".", 0x2E: "`", 0x2F: "←", 0x30: "⌫", 0x31: "↹",
            0x32: "Space", 0x33: "`", 0x34: "↩", 0x35: "⎋", 0x36: "⌘",
            0x37: "⌘", 0x38: "⇧", 0x39: "⇧", 0x3A: "⌥", 0x3B: "⌥",
            0x3C: "⌃", 0x3D: "⌃", 0x3E: "⇪", 0x3F: "F5", 0x40: "F6",
            0x41: "F7", 0x42: "F3", 0x43: "F8", 0x44: "F9", 0x45: "F11",
            0x46: "F13", 0x47: "F16", 0x48: "F14", 0x49: "F10", 0x4A: "F12",
            0x4B: "F15", 0x4C: "Ins", 0x4D: "Home", 0x4E: "PgUp", 0x4F: "Del",
            0x50: "F4", 0x51: "End", 0x52: "F2", 0x53: "PgDn", 0x54: "F1",
            0x55: "←", 0x56: "→", 0x57: "↓", 0x58: "↑"
        ]

        return keyNames[keyCode]
    }
}

/// 快捷键行组件
struct HotkeyRow: View {
    let title: String
    let hotkey: String
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.body)

            Spacer()

            Button(action: onTap) {
                Text(isRecording ? "按下组合键..." : hotkey)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isRecording ? .accentColor : .primary)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(isRecording ? 0.1 : 0.05))
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    HotkeySettingsView()
        .frame(width: 400, height: 300)
}