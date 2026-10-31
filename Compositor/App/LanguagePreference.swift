import Combine
import Foundation

/// 应用内语言偏好。
///
/// 只有一个职责：把「用户想让界面用哪种语言」这件事写进 `AppleLanguages`。
/// 界面重建、菜单勾选、重启提示全部在外面，因此这个类不 import SwiftUI / AppKit，
/// 可以脱离 App 单独编译、单独断言（见 `scripts/l10n/selftest-language.swift`）。
///
/// 三个决定成败的细节：
/// 1. **写 `AppleLanguages`，而不是自造键**。CFBundle 在进程启动时按这个键解析
///    `.lproj`，所以改动只能在下次启动生效。「跟随系统」必须写系统设置里那个
///    真实的键，否则系统设置 › 通用 › 语言与地区 › 应用程序 里的选择会和我们对不上。
/// 2. **「跟随系统」= 删键**，不是写一个猜出来的值。写死 `["en"]` 会让用户在系统
///    切到中文后仍然是英文——这是这类实现最常见的错。
/// 3. **不做进程内热切换**。热切换要重建整棵 SwiftUI 视图树并让已经取到的字符串
///    全部失效，收益低、盲区多；Apple 自己的做法也是重启。
final class LanguagePreference: ObservableObject {
    static let defaultsKey = "AppleLanguages"

    /// 已经写入了新值、但还没重启。菜单据此启用「重新启动」。
    @Published private(set) var pendingRelaunch = false

    private let store: LanguageStoring

    init(store: LanguageStoring = UserDefaults.standard) {
        self.store = store
    }

    /// 当前生效的语言（读的是磁盘上的值，不是本次会话实际渲染用的语言）。
    var current: AppLanguage {
        guard let first = store.stringArray(forKey: Self.defaultsKey)?.first else { return .system }
        if first == "en" || first.hasPrefix("en-") { return .english }
        if first.hasPrefix("zh-Hans") { return .simplifiedChinese }
        // 用户可能在系统设置里选了别的语言（如 zh-Hant、ja）。对我们来说那等于「跟随系统」。
        return .system
    }

    /// 写入偏好。返回是否真的发生了改变——没变就不该提示重启。
    @discardableResult
    func apply(_ language: AppLanguage) -> Bool {
        if language == current {
            pendingRelaunch = false
            return false
        }
        switch language {
        case .system:
            store.removeObject(forKey: Self.defaultsKey)
        case .english, .simplifiedChinese:
            store.set([language.rawValue], forKey: Self.defaultsKey)
        }
        pendingRelaunch = true
        return true
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// 写进 `AppleLanguages` 的值；`.system` 没有值，因为它表示「把键删掉」。
    var defaultsValue: String? {
        self == .system ? nil : rawValue
    }
}

/// 只为可测试而存在的窄接口。`UserDefaults` 本来就满足它，无需额外实现。
protocol LanguageStoring: AnyObject {
    func stringArray(forKey key: String) -> [String]?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: LanguageStoring {}
