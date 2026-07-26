//
//  HotKeyManager.swift
//  Launchpad_Back
//
//  Created by Claude Code on 2025/01/25.
//

import AppKit
import Carbon

/// 快捷键组合
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Command + L (默认快捷键)
    static let cmdL = HotKeyCombo(keyCode: 0x2C, modifiers: UInt32(cmdKey))

    /// Command + W
    static let cmdW = HotKeyCombo(keyCode: 0x0D, modifiers: UInt32(cmdKey))

    /// Command + Q
    static let cmdQ = HotKeyCombo(keyCode: 0x0C, modifiers: UInt32(cmdKey))

    /// 左箭头
    static let leftArrow = HotKeyCombo(keyCode: 0x7B, modifiers: 0)

    /// 右箭头
    static let rightArrow = HotKeyCombo(keyCode: 0x7C, modifiers: 0)

    /// 显示为字符串
    func displayString() -> String {
        var result = ""

        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }

        return result
    }
}

/// 快捷键管理器
/// 负责注册和管理全局快捷键
class HotKeyManager {

    // MARK: - 属性

    /// 已注册的快捷键集合
    private var registeredHotKeys: [EventHotKeyRef] = []

    /// 事件处理器引用
    private var eventHandlerRef: EventHandlerRef?

    /// 快捷键回调映射
    private var hotKeyCallbacks: [UInt32: () -> Void] = [:]

    /// 快捷键 ID 计数器
    private var hotKeyIDCounter: UInt32 = 1

    /// Carbon 事件签名
    private let eventSignature: OSType = 0x484B4D47  // "HKMG"

    // MARK: - 初始化

    init() {
        setupEventHandler()
    }

    deinit {
        unregisterAllHotKeys()
    }

    // MARK: - 公共方法

    /// 注册单个快捷键
    /// - Parameters:
    ///   - combo: 快捷键组合
    ///   - action: 触发时的回调
    /// - Returns: 注册是否成功
    func registerHotKey(_ combo: HotKeyCombo, action: @escaping () -> Void) -> Bool {
        let hotKeyID = generateHotKeyID()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyIDStruct = EventHotKeyID(signature: eventSignature, id: hotKeyID)

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyIDStruct,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            Logger.error("Failed to register hot key: \(status)")
            return false
        }

        registeredHotKeys.append(ref)
        hotKeyCallbacks[hotKeyID] = action

        Logger.info("Registered hot key: \(combo.displayString())")
        return true
    }

    /// 注销所有快捷键
    func unregisterAllHotKeys() {
        for hotKeyRef in registeredHotKeys {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotKeys.removeAll()
        hotKeyCallbacks.removeAll()

        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            eventHandlerRef = nil
        }

        Logger.info("Unregistered all hot keys")
    }

    // MARK: - 私有方法

    /// 设置事件处理器
    private func setupEventHandler() {
        var eventClass = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { handlerCallRef, event, userData in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyEvent(event)
            },
            1,
            &eventClass,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            Logger.error("Failed to install event handler: \(status)")
        }
    }

    /// 处理热键事件
    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            Logger.error("Failed to read hot key ID: \(status)")
            return status
        }

        guard hotKeyID.signature == eventSignature,
              let callback = hotKeyCallbacks[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async {
            callback()
        }

        return noErr
    }

    /// 生成下一个快捷键 ID
    private func generateHotKeyID() -> UInt32 {
        let currentID = hotKeyIDCounter
        hotKeyIDCounter = currentID + 1
        return currentID
    }
}

// MARK: - Carbon 常量

private let cmdKey: UInt32 = 0x100000
private let optionKey: UInt32 = 0x080000
private let controlKey: UInt32 = 0x040000
private let shiftKey: UInt32 = 0x020000