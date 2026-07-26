//
//  Logger.swift
//  Launchpad_Back
//
//  Created by Eric Yang on 2025/1/14.
//

import Foundation
import os.log

/// 日誌級別
enum LogLevel: String {
    case debug = "🔵 DEBUG"
    case info = "🟢 INFO"
    case warning = "🟡 WARNING"
    case error = "🔴 ERROR"
}

/// 簡單的日誌系統
struct Logger {
    private static let lock = NSLock()
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// 使用 os_log 輸出到統一日誌系統（Release 也可見），
    /// 便於診斷點擊/手勢等運行時問題。⦿ 前綴方便在 Console.app / log 流過濾。
    private static let osLog = OSLog(subsystem: "com.Eric-Yang.Launchpad-Back", category: "app")

    /// 調試日誌
    static func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }

    /// 信息日誌
    static func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    /// 警告日誌
    static func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warning, file: file, line: line)
    }

    /// 錯誤日誌
    static func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }

    /// 錯誤日誌（帶 Error 對象）
    static func error(_ error: Error, file: String = #file, line: Int = #line) {
        let message = "\(error.localizedDescription)"
        log(message, level: .error, file: file, line: line)
    }

    private static func log(_ message: String, level: LogLevel, file: String, line: Int) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let tag = "\(level.rawValue) [\(fileName):\(line)]"
        let full = "⦿ \(tag) \(message)"

        // os_log：Release 也可見。用 %{public}@ 讓字串不被隱私遮蔽。
        let type: OSLogType
        switch level {
        case .error:   type = .error
        case .warning: type = .default
        case .info:    type = .info
        case .debug:   type = .debug
        }
        os_log("%{public}@", log: osLog, type: type, full)

        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] \(tag) \(message)")
        #endif
    }
}
