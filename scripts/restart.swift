#!/usr/bin/env swift
import AppKit
import Darwin

private struct RestartError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private func run(_ executable: URL, _ arguments: [String], quiet: Bool = false) throws -> Int32 {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    if quiet { process.standardOutput = FileHandle.nullDevice }
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

@MainActor private func quit(_ app: NSRunningApplication) async throws {
    guard !app.isTerminated else { return }
    guard app.terminate() else { throw RestartError("无法请求 Monitor 正常退出。") }
    for _ in 0..<100 {
        if app.isTerminated { return }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw RestartError("Monitor 在 10 秒内没有退出。")
}

@MainActor private func launch(_ url: URL) async throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
}

@MainActor private func waitForService(_ app: NSRunningApplication) async throws {
    let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
    let arguments = ["-nP", "-a", "-p", String(app.processIdentifier), "-iTCP@127.0.0.1:47821", "-sTCP:LISTEN"]
    for _ in 0..<40 {
        guard !app.isTerminated else { throw RestartError("新版 Monitor 在启动时退出了。") }
        if try run(lsof, arguments, quiet: true) == 0 { return }
        try await Task.sleep(nanoseconds: 250_000_000)
    }
    throw RestartError("新版 Monitor 未能启动 127.0.0.1:47821 上的本机服务。")
}

private func swap(_ first: URL, _ second: URL) throws {
    guard renamex_np(first.path, second.path, UInt32(RENAME_SWAP)) == 0 else {
        throw RestartError("无法交换应用包：\(String(cString: strerror(errno)))")
    }
}

@MainActor private func restart() async throws {
    let files = FileManager.default
    let scripts = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent()
    let dist = scripts.deletingLastPathComponent().appendingPathComponent("dist")
    try files.createDirectory(at: dist, withIntermediateDirectories: true)
    let lock = open(dist.appendingPathComponent(".restart.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard lock >= 0 else { throw RestartError("无法打开重启锁。") }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw RestartError("另一个重启命令正在运行。") }

    // Build on the same volume so a signed bundle can be swapped in one operation.
    let stage = dist.appendingPathComponent(".restart-\(UUID().uuidString)")
    try files.createDirectory(at: stage, withIntermediateDirectories: false)
    let built = stage.appendingPathComponent("Monitor.app")
    let installed = dist.appendingPathComponent("Monitor.app")
    var holdsBackup = false
    defer {
        if holdsBackup { fputs("上一版应用保存在 \(built.path)\n", stderr) }
        else { try? files.removeItem(at: stage) }
    }
    guard try run(scripts.appendingPathComponent("package-release.sh"), [stage.path]) == 0,
          let identifier = Bundle(url: built)?.bundleIdentifier else {
        throw RestartError("打包未完成。")
    }

    let previous = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    let previousURL = previous.first?.bundleURL
    for app in previous { try await quit(app) }
    var started: NSRunningApplication?
    do {
        if files.fileExists(atPath: installed.path) {
            try swap(built, installed)
            holdsBackup = true
        } else {
            try files.moveItem(at: built, to: installed)
        }
        let app = try await launch(installed)
        guard app.bundleURL?.resolvingSymlinksInPath().path == installed.resolvingSymlinksInPath().path else {
            throw RestartError("启动的 Monitor 路径与打包路径不一致。")
        }
        started = app
        try await waitForService(app)
        holdsBackup = false
        print("Monitor 已重新启动，PID \(app.processIdentifier)，本机服务已就绪。\n\(installed.path)")
    } catch {
        if let started { try await quit(started) }
        if holdsBackup {
            try swap(built, installed)
            holdsBackup = false
        }
        if let previousURL { _ = try await launch(previousURL) }
        throw error
    }
}

do { try await restart() }
catch {
    fputs("重启失败：\(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
