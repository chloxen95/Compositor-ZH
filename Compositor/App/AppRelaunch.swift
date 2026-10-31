import AppKit

/// 重启自身。语言偏好在进程启动时被 CFBundle 读取，所以改完只能靠重启生效。
///
/// 用 `NSWorkspace` 而不是 `Process` 起 `/usr/bin/open`：App 是沙盒的，
/// 沙盒里能通过 LaunchServices 请求打开一个 App，但不能 fork 任意进程。
/// 先确认新实例真的起来了（`error == nil`）再退出自己，否则用户会看到程序
/// 关掉了却没再打开——比不重启更糟。
enum AppRelaunch {
    static func now() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
