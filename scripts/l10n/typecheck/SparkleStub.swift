// Sparkle 类型桩 —— 仅用于无 Xcode 环境下的静态类型检查，不参与构建，不链接进 App。
//
// 为什么需要它：Compositor 只依赖一个 SPM 包（Sparkle 2.10）。`swiftc -typecheck` 无法解析 SPM 依赖，
// 而 Xcode 才带 SPM 解析能力。此桩只声明源码中实际用到的成员，让整模块 typecheck 可以在只有
// Command Line Tools 的机器上跑通。
//
// 维护约定：上游若新增 Sparkle 调用，typecheck 会报 "no member"/"no such module"，届时只补这里的
// 声明即可，**不要**为了让检查通过而修改上游的 UpdateDriver.swift。
//
// 与真实 Sparkle 的差异是有意为之：`SPUUserDriver` 只声明 UpdateDriver 实际实现的那些方法。
// 这是安全的——协议要求更少不会让既有 conformance 失效。

import AppKit

struct SUAppcastItem {
    var isInformationOnlyUpdate = false
    var displayVersionString = ""
    var versionString = ""
    var propertiesDictionary: [String: Any] = [:]
    var dateString: String?
}

struct SPUUserUpdateState {
    enum Stage {
        case notDownloaded
        case downloaded
        case extracting
        case ready
    }
    var stage: Stage = .notDownloaded
    var userInitiated = false
}

enum SPUUserUpdateChoice {
    case dismiss
    case install
    case skip
}

struct SPUUpdatePermissionRequest {
    var systemProfile: [String: Any] = [:]
}

struct SUUpdatePermissionResponse {
    var automaticUpdateChecks = false
    var sendSystemProfile = false
}

struct SPUDownloadData {
    var data = Data()
    var textEncodingName: String?
    var mimeType: String?
}

protocol SPUUserDriver {
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void)
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void)
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void)
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData)
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error)
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void)
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void)
    func showDownloadInitiated(cancellation: @escaping () -> Void)
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64)
    func showDownloadDidReceiveData(ofLength length: UInt64)
    func showDownloadDidStartExtractingUpdate()
    func showExtractionReceivedProgress(_ progress: Double)
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void)
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void)
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void)
    func showUpdateInFocus()
    func dismissUpdateInstallation()
}

final class SPUStandardUserDriver: SPUUserDriver {
    init(hostBundle: Bundle?, delegate: Any?) {}

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {}
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {}
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {}
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}

protocol SPUUpdaterDelegate: AnyObject {}

final class SPUUpdater {
    init(hostBundle: Bundle, applicationBundle: Bundle, userDriver: SPUUserDriver, delegate: Any?) {}

    var allowsAutomaticUpdates: Bool { false }
    // 真实 Sparkle 里这个属性是可写的，UpdateDriver 会按用户偏好赋值。
    var automaticallyDownloadsUpdates = false
    var canCheckForUpdates: Bool { true }

    func start() throws {}
    func checkForUpdates() {}
    func checkForUpdatesInBackground() {}
}
