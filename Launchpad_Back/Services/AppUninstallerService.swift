//
//  AppUninstallerService.swift
//  Launchpad_Back
//
//  Created on 2026-07-27.
//
//  应用卸载服务
//  通过 NSWorkspace.shared.recycle 将 .app 移入废纸篓完成卸载。
//  本服务只负责「移入废纸篓」这一步，不触碰 ViewModel / 数据层：
//  调用方在收到 .success 后自行决定如何从列表移除该 app。
//

import AppKit
import Foundation

/// 应用卸载错误
enum AppUninstallerError: LocalizedError {
    /// 文件不存在（路径无效或已被删除）
    case fileNotFound(URL)
    /// 给定的 URL 不是 .app 包，拒绝移入废纸篓以避免误删
    case notAnAppBundle(URL)
    /// 移入废纸篓失败（无权限 / 系统保护 / 磁盘错误等）
    case recycleFailed(URL, underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Application not found at \(url.path)"
        case .notAnAppBundle(let url):
            return "\(url.path) is not an application bundle"
        case .recycleFailed(let url, let underlying):
            let detail = underlying?.localizedDescription ?? "unknown error"
            return "Failed to move \(url.path) to Trash: \(detail)"
        }
    }
}

/// 应用卸载服务
///
/// 仅提供 `moveToTrash(appURL:completion:)`，内部使用
/// `NSWorkspace.shared.recycle([appURL])`。recycle 成功（返回 true 且无 error）
/// 时才回调 `.success`；任何失败情况（无权限 / 文件不存在 / 系统保护等）
/// 均回调 `.failure`。回调始终在主线程。
final class AppUninstallerService {

    /// 将应用移入废纸篓。
    /// - Parameters:
    ///   - appURL: 应用 .app 包的 URL（例如 `URL(fileURLWithPath: app.path)`）。
    ///   - completion: 结果回调。`.success` 表示已成功移入废纸篓；
    ///     `.failure(AppUninstallerError)` 表示移入失败。始终在主线程回调。
    func moveToTrash(appURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        // NSWorkspace.recycle 的工作在内部是异步的，但回调本身是 completion handler，
        // 这里把它放到后台队列执行，避免在主线程做文件系统检查。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let result = self.performRecycle(appURL: appURL)

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// 实际执行移入废纸篓的逻辑，同步返回结果。
    ///
    /// 优先使用 FileManager.trashItem：
    /// - 纯文件系统操作，不经过 Finder/LaunchServices，**不需要辅助功能/App 管理权限**
    /// - 修复 macOS 上 NSWorkspace.recycle 反复弹"辅助功能"权限弹窗、且实际删不掉的问题
    /// 若 trashItem 失败，回退到 NSWorkspace.recycle。
    private func performRecycle(appURL: URL) -> Result<Void, Error> {
        let fm = FileManager.default

        // 1. 校验文件存在
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: appURL.path, isDirectory: &isDirectory) else {
            Logger.error("AppUninstallerService: file not found: \(appURL.path)")
            return .failure(AppUninstallerError.fileNotFound(appURL))
        }

        // 2. 校验是 .app 包（防止误把普通文件/目录移入废纸篓）
        guard isDirectory.boolValue, appURL.pathExtension == "app" else {
            Logger.error("AppUninstallerService: not an app bundle: \(appURL.path)")
            return .failure(AppUninstallerError.notAnAppBundle(appURL))
        }

        // 3. 优先使用 FileManager.trashItem（纯文件系统操作，不触发辅助功能/App 管理权限）
        do {
            try fm.trashItem(at: appURL, resultingItemURL: nil)
            Logger.info("AppUninstallerService: trashItem moved to trash: \(appURL.path)")
            return .success(())
        } catch {
            Logger.warning("AppUninstallerService: trashItem failed (\(error.localizedDescription)), falling back to NSWorkspace.recycle")
        }

        // 4. 回退：NSWorkspace.recycle
        var recycledMap: [URL: URL] = [:]
        var recycleError: Error?

        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.recycle([appURL]) { result, error in
            recycledMap = result
            recycleError = error
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 30)

        if recycleError == nil, recycledMap[appURL] != nil {
            Logger.info("AppUninstallerService: recycle moved to trash: \(appURL.path)")
            return .success(())
        }

        // 5. 精确区分错误原因
        let detail = recycleError?.localizedDescription ?? "unknown"
        Logger.error("AppUninstallerService: recycle failed for \(appURL.path): \(detail)")
        return .failure(AppUninstallerError.recycleFailed(appURL, underlying: recycleError))
    }
}
